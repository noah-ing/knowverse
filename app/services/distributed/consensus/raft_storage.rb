# frozen_string_literal: true

require 'fileutils'
require 'digest'

module Distributed
  module Consensus
    # Persistent storage for Raft state using Write-Ahead Log (WAL)
    # Provides durability guarantees required by the Raft protocol
    class RaftStorage
      # File names
      STATE_FILE = 'raft_state.json'
      LOG_FILE = 'raft_log.wal'
      SNAPSHOT_DIR = 'snapshots'

      # WAL entry markers
      ENTRY_MARKER = "\x00\x01\x02\x03"
      ENTRY_TERMINATOR = "\x03\x02\x01\x00"

      attr_reader :data_dir, :node_id

      def initialize(node_id:, data_dir: nil)
        @node_id = node_id
        @data_dir = data_dir || Rails.root.join('tmp', 'raft', node_id)
        @lock = Mutex.new
        @state_cache = nil
        @log_file = nil

        ensure_directories
      end

      # Load persistent state
      def load_state
        @lock.synchronize do
          state_path = File.join(@data_dir, STATE_FILE)
          return nil unless File.exist?(state_path)

          begin
            content = File.read(state_path)
            state = Oj.load(content, symbol_keys: true)

            # Load log entries
            state[:log] = load_log_entries

            Rails.logger.info("[RaftStorage:#{@node_id}] Loaded state: term=#{state[:term]} log=#{state[:log].length}")
            state
          rescue => e
            Rails.logger.error("[RaftStorage:#{@node_id}] Failed to load state: #{e.message}")
            nil
          end
        end
      end

      # Save current term
      def save_term(term)
        @lock.synchronize do
          update_state { |state| state[:term] = term }
        end
      end

      # Save voted_for
      def save_voted_for(voted_for)
        @lock.synchronize do
          update_state { |state| state[:voted_for] = voted_for }
        end
      end

      # Save commit_index
      def save_commit_index(commit_index)
        @lock.synchronize do
          update_state { |state| state[:commit_index] = commit_index }
        end
      end

      # Append a log entry to the WAL
      def append_log_entry(entry)
        @lock.synchronize do
          ensure_log_file_open

          # Serialize entry
          entry_data = Oj.dump(entry.to_h, mode: :compat)

          # Calculate checksum
          checksum = Digest::CRC32.hexdigest(entry_data)

          # Write entry with markers for crash recovery
          # Format: MARKER + LENGTH(4 bytes) + CHECKSUM(8 bytes) + DATA + TERMINATOR
          length = [entry_data.bytesize].pack('N')
          checksum_bytes = [checksum].pack('a8')

          @log_file.write(ENTRY_MARKER)
          @log_file.write(length)
          @log_file.write(checksum_bytes)
          @log_file.write(entry_data)
          @log_file.write(ENTRY_TERMINATOR)
          @log_file.fsync  # Ensure durability

          Rails.logger.debug("[RaftStorage:#{@node_id}] Appended entry index=#{entry.index}")
        end
      end

      # Truncate log to given index (exclusive)
      def truncate_log(last_index)
        @lock.synchronize do
          close_log_file

          # Load all entries
          entries = load_log_entries

          # Truncate
          entries = entries[0...last_index]

          # Rewrite log file
          rewrite_log(entries)

          Rails.logger.info("[RaftStorage:#{@node_id}] Truncated log to #{last_index} entries")
        end
      end

      # Create a snapshot
      def create_snapshot(last_included_index:, last_included_term:, data:)
        @lock.synchronize do
          snapshot_path = File.join(@data_dir, SNAPSHOT_DIR, "snapshot_#{last_included_index}.snap")

          snapshot = {
            last_included_index: last_included_index,
            last_included_term: last_included_term,
            timestamp: Time.now.to_i,
            data: Base64.encode64(data)
          }

          # Write atomically
          temp_path = "#{snapshot_path}.tmp"
          File.write(temp_path, Oj.dump(snapshot, mode: :compat))
          File.rename(temp_path, snapshot_path)

          # Compact log - remove entries up to snapshot
          compact_log(last_included_index)

          Rails.logger.info("[RaftStorage:#{@node_id}] Created snapshot at index=#{last_included_index}")

          snapshot_path
        end
      end

      # Load latest snapshot
      def load_latest_snapshot
        @lock.synchronize do
          snapshot_dir = File.join(@data_dir, SNAPSHOT_DIR)
          return nil unless File.directory?(snapshot_dir)

          # Find latest snapshot file
          snapshots = Dir.glob(File.join(snapshot_dir, 'snapshot_*.snap'))
          return nil if snapshots.empty?

          latest = snapshots.max_by do |path|
            match = path.match(/snapshot_(\d+)\.snap/)
            match ? match[1].to_i : 0
          end

          begin
            content = File.read(latest)
            snapshot = Oj.load(content, symbol_keys: true)
            snapshot[:data] = Base64.decode64(snapshot[:data])

            Rails.logger.info("[RaftStorage:#{@node_id}] Loaded snapshot at index=#{snapshot[:last_included_index]}")
            snapshot
          rescue => e
            Rails.logger.error("[RaftStorage:#{@node_id}] Failed to load snapshot: #{e.message}")
            nil
          end
        end
      end

      # Clean up old snapshots, keeping only the latest N
      def cleanup_snapshots(keep: 3)
        @lock.synchronize do
          snapshot_dir = File.join(@data_dir, SNAPSHOT_DIR)
          return unless File.directory?(snapshot_dir)

          snapshots = Dir.glob(File.join(snapshot_dir, 'snapshot_*.snap'))
                        .sort_by { |f| File.mtime(f) }
                        .reverse

          # Delete old snapshots beyond keep count
          snapshots[keep..-1]&.each do |path|
            File.delete(path)
            Rails.logger.info("[RaftStorage:#{@node_id}] Deleted old snapshot: #{path}")
          end
        end
      end

      # Close all file handles
      def close
        @lock.synchronize do
          close_log_file
        end
      end

      private

      def ensure_directories
        FileUtils.mkdir_p(@data_dir)
        FileUtils.mkdir_p(File.join(@data_dir, SNAPSHOT_DIR))
      end

      def update_state
        state = load_state_file || default_state
        yield(state)
        save_state_file(state)
        @state_cache = state
      end

      def load_state_file
        state_path = File.join(@data_dir, STATE_FILE)
        return nil unless File.exist?(state_path)

        Oj.load(File.read(state_path), symbol_keys: true)
      rescue => e
        Rails.logger.error("[RaftStorage:#{@node_id}] Failed to load state file: #{e.message}")
        nil
      end

      def save_state_file(state)
        state_path = File.join(@data_dir, STATE_FILE)
        temp_path = "#{state_path}.tmp"

        # Atomic write
        File.write(temp_path, Oj.dump(state, mode: :compat))
        File.rename(temp_path, state_path)
      end

      def default_state
        {
          term: 0,
          voted_for: nil,
          commit_index: 0
        }
      end

      def ensure_log_file_open
        return if @log_file && !@log_file.closed?

        log_path = File.join(@data_dir, LOG_FILE)
        @log_file = File.open(log_path, 'ab')
      end

      def close_log_file
        @log_file&.close
        @log_file = nil
      end

      def load_log_entries
        log_path = File.join(@data_dir, LOG_FILE)
        return [] unless File.exist?(log_path)

        entries = []

        File.open(log_path, 'rb') do |file|
          while !file.eof?
            entry = read_log_entry(file)
            entries << entry if entry
          end
        end

        entries
      rescue => e
        Rails.logger.error("[RaftStorage:#{@node_id}] Failed to load log: #{e.message}")
        []
      end

      def read_log_entry(file)
        # Read marker
        marker = file.read(4)
        return nil unless marker == ENTRY_MARKER

        # Read length
        length_bytes = file.read(4)
        return nil unless length_bytes
        length = length_bytes.unpack1('N')

        # Read checksum
        checksum_bytes = file.read(8)
        return nil unless checksum_bytes
        expected_checksum = checksum_bytes.unpack1('a8')

        # Read data
        data = file.read(length)
        return nil unless data && data.bytesize == length

        # Read terminator
        terminator = file.read(4)
        return nil unless terminator == ENTRY_TERMINATOR

        # Verify checksum
        actual_checksum = Digest::CRC32.hexdigest(data)
        unless actual_checksum == expected_checksum
          Rails.logger.warn("[RaftStorage:#{@node_id}] Checksum mismatch in log entry")
          return nil
        end

        # Deserialize
        entry_hash = Oj.load(data, symbol_keys: true)
        RaftNode::LogEntry.from_h(entry_hash)
      rescue => e
        Rails.logger.warn("[RaftStorage:#{@node_id}] Error reading log entry: #{e.message}")
        nil
      end

      def rewrite_log(entries)
        log_path = File.join(@data_dir, LOG_FILE)
        temp_path = "#{log_path}.tmp"

        File.open(temp_path, 'wb') do |file|
          entries.each do |entry|
            entry_data = Oj.dump(entry.to_h, mode: :compat)
            checksum = Digest::CRC32.hexdigest(entry_data)
            length = [entry_data.bytesize].pack('N')
            checksum_bytes = [checksum].pack('a8')

            file.write(ENTRY_MARKER)
            file.write(length)
            file.write(checksum_bytes)
            file.write(entry_data)
            file.write(ENTRY_TERMINATOR)
          end
          file.fsync
        end

        File.rename(temp_path, log_path)
      end

      def compact_log(last_included_index)
        close_log_file

        entries = load_log_entries
        entries = entries[last_included_index..-1] || []

        rewrite_log(entries)
      end
    end

    # CRC32 implementation for checksum
    module Digest
      class CRC32
        POLYNOMIAL = 0xEDB88320

        def self.hexdigest(data)
          crc = 0xFFFFFFFF

          data.each_byte do |byte|
            crc ^= byte
            8.times do
              if (crc & 1) == 1
                crc = (crc >> 1) ^ POLYNOMIAL
              else
                crc >>= 1
              end
            end
          end

          format('%08x', crc ^ 0xFFFFFFFF)
        end
      end
    end
  end
end
