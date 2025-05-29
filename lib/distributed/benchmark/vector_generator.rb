# frozen_string_literal: true

module Distributed
  module Benchmark
    # Generate test vectors for benchmarking the distributed system
    class VectorGenerator
      DEFAULT_DIMENSIONS = [384, 768, 1024, 1536, 2048].freeze
      DEFAULT_SEED = 12345
      
      class << self
        # Generate a single random normalized vector
        # @param dimensions [Integer] Number of dimensions for the vector
        # @param seed [Integer] Random seed for reproducibility
        # @return [Array<Float>] A normalized vector
        def random_vector(dimensions = 1536, seed = nil)
          random = seed ? Random.new(seed) : Random.new
          
          # Generate random vector
          vector = Array.new(dimensions) { random.rand(-1.0..1.0) }
          
          # Normalize the vector
          magnitude = Math.sqrt(vector.sum { |x| x * x })
          vector.map { |x| x / magnitude }
        end
        
        # Generate multiple random vectors
        # @param count [Integer] Number of vectors to generate
        # @param dimensions [Integer] Number of dimensions for each vector
        # @param seed [Integer] Random seed for reproducibility
        # @return [Array<Array<Float>>] Array of normalized vectors
        def random_vectors(count, dimensions = 1536, seed = DEFAULT_SEED)
          random = Random.new(seed)
          progress = nil
          
          if count > 1000
            begin
              require 'ruby-progressbar'
              progress = ProgressBar.create(
                title: "Generating #{count} vectors",
                total: count,
                format: '%t: |%B| %p%% %e'
              )
            rescue LoadError
              # No progress bar if gem not available
            end
          end
          
          Array.new(count) do |i|
            progress&.increment
            random_vector(dimensions, random.rand(100000))
          end
        end
        
        # Generate synthetic document data with embeddings
        # @param organization_id [Integer] ID of the organization
        # @param count [Integer] Number of documents to generate
        # @param dimensions_array [Array<Integer>] Dimensions to generate vectors for
        # @param seed [Integer] Random seed for reproducibility
        # @return [Array<Hash>] Array of document data with embeddings
        def synthetic_documents(organization_id, count, dimensions_array = DEFAULT_DIMENSIONS, seed = DEFAULT_SEED)
          random = Random.new(seed)
          progress = nil
          
          if count > 100
            begin
              require 'ruby-progressbar'
              progress = ProgressBar.create(
                title: "Generating #{count} documents",
                total: count,
                format: '%t: |%B| %p%% %e'
              )
            rescue LoadError
              # No progress bar if gem not available
            end
          end
          
          documents = []
          
          count.times do |i|
            # Generate a synthetic document
            doc = {
              title: "Test Document #{i + 1}",
              content: generate_lorem_ipsum(random.rand(3..10)),
              organization_id: organization_id,
              created_at: Time.now - random.rand(0..30).days,
              embeddings: {}
            }
            
            # Generate embeddings for each dimension
            dimensions_array.each do |dim|
              doc[:embeddings][dim] = random_vector(dim, random.rand(100000))
            end
            
            documents << doc
            progress&.increment
          end
          
          documents
        end
        
        # Batch insert documents into the database with vector embeddings
        # @param documents [Array<Hash>] Documents with embeddings
        # @return [Integer] Number of documents inserted
        def batch_insert_documents(documents)
          return 0 if documents.empty?
          
          organization_id = documents.first[:organization_id]
          
          ActiveRecord::Base.transaction do
            documents.each do |doc|
              # Create document
              document = Document.create!(
                title: doc[:title],
                content: doc[:content],
                organization_id: organization_id,
                status: 'processed'
              )
              
              # Create embeddings for each dimension
              doc[:embeddings].each do |dimension, vector|
                model_name = dimension_to_model_name(dimension)
                
                VectorEmbedding.create!(
                  document: document,
                  model: model_name,
                  dimensions: dimension,
                  embedding: vector
                )
              end
            end
          end
          
          documents.size
        end
        
        # Generate organization test data with documents and embeddings
        # @param name [String] Organization name
        # @param document_count [Integer] Number of documents to generate
        # @param dimensions_array [Array<Integer>] Dimensions to generate vectors for
        # @return [Organization] Created organization with documents
        def generate_test_organization(name, document_count, dimensions_array = DEFAULT_DIMENSIONS)
          org = Organization.create!(
            name: name,
            slug: name.parameterize
          )
          
          # Create owner user
          user = User.create!(
            email: "owner@#{name.parameterize}.example.com",
            status: 'active'
          )
          
          # Create organization membership
          OrganizationUser.create!(
            organization: org,
            user: user,
            role: 'owner'
          )
          
          # Generate documents in batches
          batch_size = [100, document_count].min
          remaining = document_count
          
          while remaining > 0
            batch_count = [batch_size, remaining].min
            docs = synthetic_documents(org.id, batch_count, dimensions_array)
            batch_insert_documents(docs)
            remaining -= batch_count
          end
          
          org
        end
        
        # Generate a multi-node test cluster with organizations and documents
        # @param node_count [Integer] Number of nodes in the cluster
        # @param org_count [Integer] Number of organizations to create
        # @param docs_per_org [Integer] Number of documents per organization
        # @return [Hash] Test cluster configuration
        def generate_test_cluster(node_count, org_count, docs_per_org)
          # Clean up any existing data
          cleanup_test_data
          
          # Create node configuration
          nodes = Array.new(node_count) do |i|
            {
              node_id: "test-node-#{i + 1}",
              host: "localhost",
              port: 3000 + i
            }
          end
          
          # Create organizations with documents
          organizations = []
          org_count.times do |i|
            org = generate_test_organization("Test Org #{i + 1}", docs_per_org)
            organizations << org
          end
          
          {
            nodes: nodes,
            organizations: organizations,
            total_documents: docs_per_org * org_count
          }
        end
        
        # Clean up test data
        def cleanup_test_data
          # Find all test organizations
          test_orgs = Organization.where("name LIKE 'Test Org %'")
          
          # Delete all associated data
          test_orgs.each do |org|
            org.documents.destroy_all
            org.organization_users.destroy_all
          end
          
          # Delete the organizations
          test_orgs.destroy_all
        end
        
        private
        
        # Map dimension to model name
        def dimension_to_model_name(dimension)
          case dimension
          when 384
            'mini'
          when 768
            'small'
          when 1024
            'base'
          when 1536
            'large'
          when 2048
            'xl'
          else
            'custom'
          end
        end
        
        # Generate lorem ipsum text
        def generate_lorem_ipsum(paragraphs)
          lorem = []
          paragraphs.times do
            sentences = rand(3..8)
            paragraph = []
            
            sentences.times do
              words = rand(5..15)
              sentence = lorem_words.sample(words).join(' ')
              paragraph << sentence.capitalize + '.'
            end
            
            lorem << paragraph.join(' ')
          end
          
          lorem.join("\n\n")
        end
        
        # List of lorem ipsum words
        def lorem_words
          %w[
            lorem ipsum dolor sit amet consectetur adipiscing elit sed do
            eiusmod tempor incididunt ut labore et dolore magna aliqua ut
            enim ad minim veniam quis nostrud exercitation ullamco laboris
            nisi ut aliquip ex ea commodo consequat duis aute irure dolor
            in reprehenderit in voluptate velit esse cillum dolore eu fugiat
            nulla pariatur excepteur sint occaecat cupidatat non proident
            sunt in culpa qui officia deserunt mollit anim id est laborum
          ]
        end
      end
    end
  end
end
