#!/usr/bin/env ruby
# frozen_string_literal: true

# Import documents from a directory into KnowVerse
# Usage: rails runner scripts/import_directory.rb /path/to/directory [--dry-run]

require 'fileutils'

class DirectoryImporter
  SUPPORTED_EXTENSIONS = %w[
    .pdf .docx .doc .txt .rtf .md
    .xlsx .xls .csv
    .html .htm .rst .xml .json .yaml .yml
  ].freeze

  MIME_TYPES = {
    '.pdf' => 'application/pdf',
    '.docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.doc' => 'application/msword',
    '.txt' => 'text/plain',
    '.rtf' => 'text/rtf',
    '.md' => 'text/markdown',
    '.xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    '.xls' => 'application/vnd.ms-excel',
    '.csv' => 'text/csv',
    '.html' => 'text/html',
    '.htm' => 'text/html',
    '.rst' => 'text/x-rst',
    '.xml' => 'application/xml',
    '.json' => 'application/json',
    '.yaml' => 'application/x-yaml',
    '.yml' => 'application/x-yaml'
  }.freeze

  attr_reader :directory, :dry_run, :results

  def initialize(directory:, dry_run: false)
    @directory = directory
    @dry_run = dry_run
    @results = {
      started_at: Time.current,
      files_found: 0,
      files_imported: 0,
      files_skipped: 0,
      files_errored: 0,
      total_size_mb: 0,
      errors: []
    }
  end

  def run
    validate_directory!
    setup_environment

    files = scan_directory
    @results[:files_found] = files.size

    print_summary(files)

    if @dry_run
      puts "\n[DRY RUN] Would import #{files.size} files"
      return
    end

    puts "\n"
    print "Proceed with import? (y/n): "
    response = $stdin.gets&.chomp&.downcase
    unless response == 'y'
      puts "Import cancelled."
      return
    end

    import_files(files)
    print_results
  end

  private

  def validate_directory!
    unless File.directory?(@directory)
      puts "ERROR: #{@directory} is not a valid directory"
      exit 1
    end
  end

  def setup_environment
    @organization = Organization.first
    @user = User.first

    unless @organization && @user
      puts "ERROR: No organization or user found. Please create one first."
      exit 1
    end

    puts "=" * 60
    puts "📁 KNOWVERSE DIRECTORY IMPORT"
    puts "=" * 60
    puts "Directory: #{@directory}"
    puts "Organization: #{@organization.name} (ID: #{@organization.id})"
    puts "User: #{@user.email}"
    puts "=" * 60
  end

  def scan_directory
    files = []

    Dir.glob(File.join(@directory, '**', '*')).each do |path|
      next unless File.file?(path)
      next if File.basename(path).start_with?('.')  # Skip hidden files

      ext = File.extname(path).downcase
      next unless SUPPORTED_EXTENSIONS.include?(ext)

      size = File.size(path)
      @results[:total_size_mb] += size / 1_000_000.0

      files << {
        path: path,
        filename: File.basename(path),
        extension: ext,
        size: size,
        size_human: human_size(size)
      }
    end

    files.sort_by { |f| f[:filename] }
  end

  def print_summary(files)
    puts "\n📊 Files Found:"

    # Group by extension
    by_ext = files.group_by { |f| f[:extension] }
    by_ext.each do |ext, group|
      total_size = group.sum { |f| f[:size] }
      puts "   #{ext.ljust(8)} #{group.size.to_s.rjust(3)} files  (#{human_size(total_size)})"
    end

    puts "\n   TOTAL: #{files.size} files (#{human_size(@results[:total_size_mb] * 1_000_000)})"

    # Show largest files
    puts "\n📄 Largest Files:"
    files.sort_by { |f| -f[:size] }.first(5).each do |f|
      puts "   #{f[:size_human].rjust(10)}  #{f[:filename]}"
    end
  end

  def import_files(files)
    # Create bulk upload record
    @bulk_upload = BulkUpload.create!(
      organization: @organization,
      user: @user,
      total_files: files.size,
      metadata: {
        source: 'directory_import',
        directory: @directory,
        started_at: Time.current.iso8601
      }
    )
    @bulk_upload.start!

    puts "\n🚀 Starting import (BulkUpload ##{@bulk_upload.id})...\n"

    files.each_with_index do |file_info, index|
      import_single_file(file_info, index, files.size)
    end

    @bulk_upload.update!(
      completed_at: Time.current,
      status: @results[:files_errored].zero? ? 'completed' : 'partial'
    )
  end

  def import_single_file(file_info, index, total)
    progress = ((index + 1).to_f / total * 100).round(1)
    print "\r   [#{progress.to_s.rjust(5)}%] Importing: #{file_info[:filename].truncate(40)}..."

    # Check if already exists
    existing = @organization.documents.find_by(title: file_info[:filename])
    if existing
      @results[:files_skipped] += 1
      print " SKIPPED (exists)\n" if index < 10 || (index + 1) % 10 == 0
      return
    end

    # Create document
    document = Document.new(
      title: file_info[:filename],
      organization: @organization,
      bulk_upload: @bulk_upload,
      status: 'pending',
      embedding_status: 'pending',
      metadata: {
        original_path: file_info[:path],
        file_size: file_info[:size],
        imported_at: Time.current.iso8601
      }
    )

    # Read file content into memory and attach
    file_content = File.binread(file_info[:path])
    document.file.attach(
      io: StringIO.new(file_content),
      filename: file_info[:filename],
      content_type: MIME_TYPES[file_info[:extension]] || 'application/octet-stream'
    )

    document.save!

    # Queue for processing
    DocumentProcessing::TextExtractionWorker.perform_later(document.id)

    @results[:files_imported] += 1

  rescue => e
    @results[:files_errored] += 1
    @results[:errors] << { file: file_info[:filename], error: e.message }
    print " ERROR: #{e.message.truncate(50)}\n"
  end

  def print_results
    @results[:finished_at] = Time.current
    duration = @results[:finished_at] - @results[:started_at]

    puts "\n\n" + "=" * 60
    puts "📊 IMPORT RESULTS"
    puts "=" * 60
    puts "   Files found:    #{@results[:files_found]}"
    puts "   Files imported: #{@results[:files_imported]}"
    puts "   Files skipped:  #{@results[:files_skipped]}"
    puts "   Files errored:  #{@results[:files_errored]}"
    puts "   Total size:     #{@results[:total_size_mb].round(2)} MB"
    puts "   Duration:       #{duration.round(1)}s"
    puts "   BulkUpload ID:  #{@bulk_upload&.id}"

    if @results[:errors].any?
      puts "\n❌ Errors:"
      @results[:errors].first(10).each do |err|
        puts "   #{err[:file]}: #{err[:error]}"
      end
    end

    puts "\n✅ Documents are now queued for processing!"
    puts "   Monitor progress: rails runner 'puts BulkUpload.find(#{@bulk_upload&.id}).summary.to_json'"
    puts "=" * 60
  end

  def human_size(bytes)
    return '0 B' if bytes.zero?

    units = %w[B KB MB GB]
    exp = (Math.log(bytes) / Math.log(1024)).to_i
    exp = units.size - 1 if exp >= units.size

    "%.1f %s" % [bytes.to_f / (1024 ** exp), units[exp]]
  end
end

# Parse arguments
directory = ARGV[0]
dry_run = ARGV.include?('--dry-run')

unless directory
  puts "Usage: rails runner scripts/import_directory.rb /path/to/directory [--dry-run]"
  exit 1
end

# Run import
importer = DirectoryImporter.new(directory: directory, dry_run: dry_run)
importer.run
