#!/usr/bin/env ruby
require_relative '../config/environment'

# Create a test document
org = Organization.first
doc = Document.create!(
  title: 'Manual Test Document',
  content: 'This is a test document for direct processing.',
  organization_id: org.id,
  status: 'pending',
  embedding_status: 'pending'
)

puts "Created document with ID: #{doc.id}"
