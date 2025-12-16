# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module Distributed
  module Consensus
    # HTTP-based RPC transport for Raft inter-node communication
    class RaftRPC
      # Default configuration
      DEFAULT_PORT = 7100
      CONNECTION_TIMEOUT = 2
      READ_TIMEOUT = 5

      def initialize(node_id:, peers: {})
        @node_id = node_id
        @peers = peers  # Hash of node_id => { host:, port: }
        @connections = Concurrent::Hash.new
      end

      # Update peer list
      def update_peers(peers)
        @peers = peers
        # Close any stale connections
        @connections.keys.each do |node_id|
          unless @peers.key?(node_id)
            @connections.delete(node_id)
          end
        end
      end

      # Send RequestVote RPC to a peer
      def request_vote(peer_id, term:, candidate_id:, last_log_index:, last_log_term:)
        payload = {
          rpc_type: 'request_vote',
          term: term,
          candidate_id: candidate_id,
          last_log_index: last_log_index,
          last_log_term: last_log_term
        }

        response = send_rpc(peer_id, payload)

        {
          term: response['term'],
          vote_granted: response['vote_granted']
        }
      end

      # Send AppendEntries RPC to a peer
      def append_entries(peer_id, term:, leader_id:, prev_log_index:, prev_log_term:, entries:, leader_commit:)
        payload = {
          rpc_type: 'append_entries',
          term: term,
          leader_id: leader_id,
          prev_log_index: prev_log_index,
          prev_log_term: prev_log_term,
          entries: entries.map(&:to_h),
          leader_commit: leader_commit
        }

        response = send_rpc(peer_id, payload)

        {
          term: response['term'],
          success: response['success'],
          match_index: response['match_index']
        }
      end

      # Send InstallSnapshot RPC to a peer (for log compaction)
      def install_snapshot(peer_id, term:, leader_id:, last_included_index:, last_included_term:, offset:, data:, done:)
        payload = {
          rpc_type: 'install_snapshot',
          term: term,
          leader_id: leader_id,
          last_included_index: last_included_index,
          last_included_term: last_included_term,
          offset: offset,
          data: Base64.encode64(data),
          done: done
        }

        response = send_rpc(peer_id, payload)

        {
          term: response['term']
        }
      end

      # Forward a client request to the leader
      def forward_to_leader(leader_id, command)
        payload = {
          rpc_type: 'forward_command',
          command: command
        }

        response = send_rpc(leader_id, payload)

        {
          success: response['success'],
          error: response['error'],
          index: response['index'],
          term: response['term']
        }
      end

      private

      def send_rpc(peer_id, payload)
        peer_info = @peers[peer_id]
        raise "Unknown peer: #{peer_id}" unless peer_info

        uri = URI("http://#{peer_info[:host]}:#{peer_info[:port] || DEFAULT_PORT}/raft/rpc")

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['X-Raft-Node-ID'] = @node_id
        request.body = JSON.generate(payload)

        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = CONNECTION_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise "RPC failed with status #{response.code}: #{response.body}"
        end

        JSON.parse(response.body)
      rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError => e
        Rails.logger.warn("[RaftRPC] Connection to #{peer_id} failed: #{e.class} - #{e.message}")
        raise RPCError, "Connection to #{peer_id} failed: #{e.message}"
      rescue JSON::ParserError => e
        Rails.logger.error("[RaftRPC] Invalid JSON response from #{peer_id}: #{e.message}")
        raise RPCError, "Invalid response from #{peer_id}"
      end

      # Custom error class for RPC failures
      class RPCError < StandardError; end
    end

    # Rails controller mixin for handling incoming Raft RPCs
    module RaftRPCHandler
      extend ActiveSupport::Concern

      included do
        skip_before_action :verify_authenticity_token, only: [:raft_rpc]
        before_action :validate_raft_request, only: [:raft_rpc]
      end

      def raft_rpc
        payload = JSON.parse(request.body.read)
        sender_id = request.headers['X-Raft-Node-ID']

        response = case payload['rpc_type']
        when 'request_vote'
          handle_request_vote(payload)
        when 'append_entries'
          handle_append_entries(payload)
        when 'install_snapshot'
          handle_install_snapshot(payload)
        when 'forward_command'
          handle_forward_command(payload)
        else
          { error: "Unknown RPC type: #{payload['rpc_type']}" }
        end

        render json: response
      rescue JSON::ParserError => e
        render json: { error: "Invalid JSON: #{e.message}" }, status: :bad_request
      rescue => e
        Rails.logger.error("[RaftRPC] Handler error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        render json: { error: e.message }, status: :internal_server_error
      end

      private

      def validate_raft_request
        unless request.headers['X-Raft-Node-ID'].present?
          render json: { error: 'Missing X-Raft-Node-ID header' }, status: :bad_request
          return false
        end
        true
      end

      def handle_request_vote(payload)
        response = RaftNode.instance.handle_request_vote(
          term: payload['term'],
          candidate_id: payload['candidate_id'],
          last_log_index: payload['last_log_index'],
          last_log_term: payload['last_log_term']
        )

        {
          term: response[:term],
          vote_granted: response[:vote_granted]
        }
      end

      def handle_append_entries(payload)
        entries = (payload['entries'] || []).map do |entry|
          RaftNode::LogEntry.from_h(entry.deep_symbolize_keys)
        end

        response = RaftNode.instance.handle_append_entries(
          term: payload['term'],
          leader_id: payload['leader_id'],
          prev_log_index: payload['prev_log_index'],
          prev_log_term: payload['prev_log_term'],
          entries: entries,
          leader_commit: payload['leader_commit']
        )

        {
          term: response[:term],
          success: response[:success],
          match_index: response[:match_index]
        }
      end

      def handle_install_snapshot(payload)
        data = Base64.decode64(payload['data'])

        response = RaftNode.instance.handle_install_snapshot(
          term: payload['term'],
          leader_id: payload['leader_id'],
          last_included_index: payload['last_included_index'],
          last_included_term: payload['last_included_term'],
          offset: payload['offset'],
          data: data,
          done: payload['done']
        )

        {
          term: response[:term]
        }
      end

      def handle_forward_command(payload)
        response = RaftNode.instance.submit_command(
          payload['command'].deep_symbolize_keys
        )

        {
          success: response[:success],
          error: response[:error],
          index: response[:index],
          term: response[:term]
        }
      end
    end
  end
end
