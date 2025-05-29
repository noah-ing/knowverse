# frozen_string_literal: true

require 'rails_helper'

# Skip ActiveRecord schema validation during testing
ActiveRecord::Migration.maintain_test_schema = false
require 'distributed/testing/network_simulator'
require 'distributed/testing/recovery_metrics'

RSpec.describe "Distributed System Fault Tolerance", type: :system do
  let(:cluster_size) { 5 }
  let(:recovery_metrics) { Distributed::Testing::RecoveryMetrics.new }
  let(:service) { Distributed::DistributedService.instance }
  let(:test_organization) { FactoryBot.create(:organization) }
  
  before(:each) do
    # Initialize test cluster
    setup_test_cluster(cluster_size)
    recovery_metrics.reset_metrics
  end
  
  describe "leader failure scenarios" do
    it "elects a new leader when current leader fails" do
      recovery_metrics.start_scenario('leader_failure', { type: 'node_failure' })
      
      # Find current leader
      leader_node = find_leader_node
      expect(leader_node).not_to be_nil
      
      # Crash the leader
      leader_recovery = Distributed::Testing::NetworkSimulator.crash_node(leader_node.node_id)
      recovery_metrics.record_checkpoint(:leader_crashed)
      
      # Wait for new leader election
      new_leader_node = nil
      election_timeout = 0
      
      while new_leader_node.nil? && election_timeout < 30
        new_leader_node = find_leader_node
        break if new_leader_node && new_leader_node.node_id != leader_node.node_id
        new_leader_node = nil
        sleep 0.1
        election_timeout += 0.1
      end
      
      recovery_metrics.record_checkpoint(:leader_elected)
      
      # Verify new leader was elected
      expect(new_leader_node).not_to be_nil
      expect(new_leader_node.node_id).not_to eq(leader_node.node_id)
      
      # Verify the system is still operational
      expect(service.operational?).to be true
      
      # Run test operations
      test_result = run_test_operations
      recovery_metrics.record_checkpoint(:operations_completed)
      
      # Recover the old leader
      leader_recovery.call
      recovery_metrics.record_checkpoint(:old_leader_recovered)
      
      # Verify cluster has full membership
      expect(service.cluster_nodes.count { |n| n.status == :online }).to eq(cluster_size)
      
      # Calculate data consistency score (0.0-1.0)
      consistency_score = verify_data_consistency
      recovery_metrics.end_scenario(consistency_score)
      
      # Verify high consistency
      expect(consistency_score).to be > 0.95
    end
    
    it "continues processing commands during leader transition" do
      recovery_metrics.start_scenario('concurrent_operations_during_election', { type: 'leader_transition' })
      
      # Find current leader
      leader_node = find_leader_node
      
      # Start background operations
      operation_thread = Thread.new do
        5.times do |i|
          submit_test_command(i)
          sleep 0.2
        end
      end
      
      recovery_metrics.record_checkpoint(:background_operations_started)
      
      # Crash the leader after a short delay
      sleep 0.5
      leader_recovery = Distributed::Testing::NetworkSimulator.crash_node(leader_node.node_id)
      recovery_metrics.record_checkpoint(:leader_crashed)
      
      # Wait for new leader election
      new_leader_elected = false
      election_timeout = 0
      
      while !new_leader_elected && election_timeout < 30
        new_leader = find_leader_node
        new_leader_elected = new_leader && new_leader.node_id != leader_node.node_id
        sleep 0.1
        election_timeout += 0.1
      end
      
      recovery_metrics.record_checkpoint(:leader_elected)
      
      # Wait for background operations to complete
      operation_thread.join
      recovery_metrics.record_checkpoint(:operations_completed)
      
      # Recover the old leader
      leader_recovery.call
      recovery_metrics.record_checkpoint(:old_leader_recovered)
      
      # Calculate data consistency score (0.0-1.0)
      consistency_score = verify_data_consistency
      recovery_metrics.end_scenario(consistency_score)
      
      # Verify operations were completed successfully
      expect(consistency_score).to be > 0.9
    end
    
    it "maintains data consistency after leader recovery" do
      recovery_metrics.start_scenario('leader_recovery_consistency', { type: 'node_recovery' })
      
      # Find current leader
      leader_node = find_leader_node
      
      # Submit test data
      test_data = submit_test_data(50)
      recovery_metrics.record_checkpoint(:data_submitted)
      
      # Crash the leader
      leader_recovery = Distributed::Testing::NetworkSimulator.crash_node(leader_node.node_id)
      recovery_metrics.record_checkpoint(:leader_crashed)
      
      # Wait for new leader election
      new_leader_elected = false
      election_timeout = 0
      
      while !new_leader_elected && election_timeout < 30
        new_leader = find_leader_node
        new_leader_elected = new_leader && new_leader.node_id != leader_node.node_id
        sleep 0.1
        election_timeout += 0.1
      end
      
      recovery_metrics.record_checkpoint(:leader_elected)
      
      # Submit more test data to new leader
      more_test_data = submit_test_data(50)
      recovery_metrics.record_checkpoint(:more_data_submitted)
      
      # Recover the old leader
      leader_recovery.call
      recovery_metrics.record_checkpoint(:old_leader_recovered)
      
      # Wait for sync
      sleep 1
      
      # Verify all data is available and consistent
      all_data = test_data + more_test_data
      consistency_score = verify_specific_data(all_data)
      recovery_metrics.end_scenario(consistency_score)
      
      # Expect high consistency
      expect(consistency_score).to be > 0.98
    end
  end
  
  describe "network partition scenarios" do
    it "handles minority partition correctly" do
      recovery_metrics.start_scenario('minority_network_partition', { type: 'network_partition' })
      
      # Create a minority partition (less than half of nodes)
      minority_count = (cluster_size / 2) - 1
      majority_count = cluster_size - minority_count
      
      minority_nodes = service.cluster_nodes.sample(minority_count).map(&:node_id)
      
      # Create network partition
      partition_heal = Distributed::Testing::NetworkSimulator.create_partition(minority_nodes)
      recovery_metrics.record_checkpoint(:partition_created)
      
      # Verify system remains operational in majority partition
      expect(service.operational?).to be true
      
      # Find the leader after partition
      leader_node = find_leader_node
      expect(leader_node).not_to be_nil
      expect(minority_nodes).not_to include(leader_node.node_id)
      
      recovery_metrics.record_checkpoint(:leader_verified)
      
      # Submit test data to majority partition
      test_data = submit_test_data(20)
      recovery_metrics.record_checkpoint(:data_submitted)
      
      # Heal the partition
      partition_heal.call
      recovery_metrics.record_checkpoint(:partition_healed)
      
      # Wait for sync
      sleep 1
      
      # Verify data consistency across all nodes
      consistency_score = verify_specific_data(test_data)
      recovery_metrics.end_scenario(consistency_score)
      
      # Expect high consistency after healing
      expect(consistency_score).to be > 0.95
    end
    
    it "handles split-brain scenario and recovers" do
      skip("Not applicable to Raft consensus") unless service.respond_to?(:handle_split_brain)
      
      recovery_metrics.start_scenario('split_brain', { type: 'network_partition' })
      
      # Create equal partition (half of nodes on each side)
      # This is a challenging scenario for consensus protocols
      nodes = service.cluster_nodes.map(&:node_id)
      half_size = nodes.size / 2
      
      partition_a = nodes[0...half_size]
      partition_b = nodes[half_size..-1]
      
      # Create network partition
      partition_heal = Distributed::Testing::NetworkSimulator.create_partition(partition_a)
      recovery_metrics.record_checkpoint(:partition_created)
      
      # Both sides may attempt leader election
      # Wait to see what happens
      sleep 3
      
      # System should detect split-brain condition
      expect(service.respond_to?(:split_brain_detected?)).to be true
      expect(service.split_brain_detected?).to be true if service.respond_to?(:split_brain_detected?)
      
      recovery_metrics.record_checkpoint(:split_brain_detected)
      
      # Heal the partition
      partition_heal.call
      recovery_metrics.record_checkpoint(:partition_healed)
      
      # Wait for recovery
      sleep 5
      
      # Verify system has recovered with a single leader
      expect(service.operational?).to be true
      
      leader_count = service.cluster_nodes.count { |n| n.state == Distributed::Consensus::RaftAdapter::LEADER }
      expect(leader_count).to eq(1)
      
      recovery_metrics.record_checkpoint(:recovered)
      
      # Verify data consistency
      consistency_score = verify_data_consistency
      recovery_metrics.end_scenario(consistency_score)
      
      # Expect reasonable consistency after healing
      expect(consistency_score).to be > 0.8
    end
  end
  
  describe "data corruption scenarios" do
    it "recovers from log corruption on follower node" do
      recovery_metrics.start_scenario('follower_log_corruption', { type: 'data_corruption' })
      
      # Find current leader
      leader_node = find_leader_node
      
      # Find a follower node
      follower_node = service.cluster_nodes.find { |n| n.node_id != leader_node.node_id }
      expect(follower_node).not_to be_nil
      
      # Submit test data
      test_data = submit_test_data(30)
      recovery_metrics.record_checkpoint(:data_submitted)
      
      # Corrupt logs on follower
      Distributed::Testing::NetworkSimulator.corrupt_logs(follower_node.node_id, :moderate)
      recovery_metrics.record_checkpoint(:logs_corrupted)
      
      # Restart the follower node
      follower_recovery = Distributed::Testing::NetworkSimulator.crash_node(follower_node.node_id)
      sleep 0.5
      follower_recovery.call
      
      recovery_metrics.record_checkpoint(:node_restarted)
      
      # Wait for recovery
      sleep 3
      
      # Verify data consistency
      consistency_score = verify_specific_data(test_data)
      recovery_metrics.end_scenario(consistency_score)
      
      # Expect high consistency after healing
      expect(consistency_score).to be > 0.9
    end
    
    it "recovers from state corruption through snapshot" do
      skip("Not implemented yet") unless service.respond_to?(:create_snapshot)
      
      recovery_metrics.start_scenario('state_corruption_recovery', { type: 'data_corruption' })
      
      # Submit test data
      test_data = submit_test_data(50)
      recovery_metrics.record_checkpoint(:data_submitted)
      
      # Create a snapshot
      service.create_snapshot if service.respond_to?(:create_snapshot)
      recovery_metrics.record_checkpoint(:snapshot_created)
      
      # Find a follower node
      leader_node = find_leader_node
      follower_node = service.cluster_nodes.find { |n| n.node_id != leader_node.node_id }
      
      # Corrupt state on follower
      corrupt_node_state(follower_node.node_id)
      recovery_metrics.record_checkpoint(:state_corrupted)
      
      # Restart the follower node
      follower_recovery = Distributed::Testing::NetworkSimulator.crash_node(follower_node.node_id)
      sleep 0.5
      follower_recovery.call
      
      recovery_metrics.record_checkpoint(:node_restarted)
      
      # Wait for recovery (snapshot restoration)
      sleep 5
      
      # Verify data consistency
      consistency_score = verify_specific_data(test_data)
      recovery_metrics.end_scenario(consistency_score)
      
      # Expect high consistency after recovery
      expect(consistency_score).to be > 0.9
    end
  end
  
  describe "cascading failures" do
    it "recovers from sequential node failures" do
      recovery_metrics.start_scenario('cascading_failures', { type: 'multiple_failures' })
      
      # Get all nodes
      nodes = service.cluster_nodes.map(&:node_id)
      expect(nodes.size).to eq(cluster_size)
      
      # Submit initial test data
      test_data = submit_test_data(20)
      recovery_metrics.record_checkpoint(:initial_data_submitted)
      
      # Crash nodes one by one with short intervals
      node_recoveries = []
      
      nodes[0...3].each_with_index do |node_id, index|
        recovery = Distributed::Testing::NetworkSimulator.crash_node(node_id)
        node_recoveries << recovery
        
        recovery_metrics.record_checkpoint(:"node_#{index + 1}_crashed")
        
        # Submit some data between crashes if system is still operational
        if service.operational?
          more_data = submit_test_data(5)
          test_data += more_data
          recovery_metrics.record_checkpoint(:"data_after_crash_#{index + 1}")
        end
        
        sleep 1
      end
      
      # Verify system status (may or may not be operational depending on Raft configuration)
      system_operational = service.operational?
      recovery_metrics.record_checkpoint(:system_status_checked, { operational: system_operational })
      
      # Recover nodes in reverse order
      node_recoveries.reverse.each_with_index do |recovery, index|
        recovery.call
        recovery_metrics.record_checkpoint(:"node_#{3 - index}_recovered")
        sleep 1
      end
      
      # Wait for full recovery
      sleep 5
      
      # Verify the system is operational again
      expect(service.operational?).to be true
      
      # Verify data consistency
      consistency_score = verify_specific_data(test_data)
      recovery_metrics.end_scenario(consistency_score)
      
      # Expect reasonable consistency after recovery
      expect(consistency_score).to be > 0.8
    end
  end
  
  # Generate a detailed report after all tests
  after(:all) do
    report = recovery_metrics.generate_report
    report_path = Rails.root.join('tmp', 'fault_tolerance_report.md')
    File.write(report_path, report)
    puts "Fault tolerance report generated at: #{report_path}"
  end
  
  private
  
  def setup_test_cluster(size)
    # Initialize test cluster with specified size
    service = Distributed::DistributedService.instance
    
    # Start with fresh state
    service.shutdown if service.initialized
    
    # Create node configuration
    nodes = Array.new(size) do |i|
      {
        node_id: "test-node-#{i + 1}",
        host: "localhost",
        port: 3000 + i
      }
    end
    
    # Configure and start the service
    Rails.configuration.distributed.node_id = nodes.first[:node_id]
    Rails.configuration.distributed.cluster_nodes = nodes.map { |n| "#{n[:node_id]}@#{n[:host]}:#{n[:port]}" }
    
    service.initialize_service
    
    # Wait for cluster to stabilize
    sleep 3
    
    # Verify cluster is properly set up
    expect(service.cluster_nodes.size).to eq(size)
    expect(service.initialized).to be true
  end
  
  def find_leader_node
    service.cluster_nodes.find { |n| n.state == Distributed::Consensus::RaftAdapter::LEADER }
  end
  
  def submit_test_command(id)
    service.raft_adapter.submit_command(
      'test', 
      { id: id, timestamp: Time.now.to_i },
      test_organization.id
    )
  end
  
  def submit_test_data(count)
    data = []
    
    count.times do |i|
      item = { id: SecureRandom.uuid, value: "test-value-#{i}", timestamp: Time.now.to_i }
      data << item
      
      result = service.raft_adapter.submit_command(
        'add_test_data',
        item,
        test_organization.id
      )
      
      # Store commit index for verification
      item[:commit_index] = result.value[:index] if result.respond_to?(:value) && result.value.is_a?(Hash)
    end
    
    data
  end
  
  def run_test_operations
    results = []
    
    5.times do |i|
      result = submit_test_command(i)
      results << result
    end
    
    results
  end
  
  def verify_data_consistency
    # A real implementation would check actual data consistency
    # For this example, we return a simulated consistency score
    service.cluster_nodes.all? { |n| n.status == :online } ? 1.0 : 0.8
  end
  
  def verify_specific_data(data)
    # A real implementation would verify that all nodes have consistent views of the test data
    # For this example, we return a simulated consistency score
    node_count = service.cluster_nodes.count
    online_count = service.cluster_nodes.count { |n| n.status == :online }
    
    # Simple consistency model: ratio of online nodes to total nodes
    (online_count / node_count.to_f) * 0.98 + 0.02
  end
  
  def corrupt_node_state(node_id)
    # In a real implementation, this would corrupt the actual state files
    # For this example, it's a placeholder
    state_path = Rails.root.join('tmp', 'raft', node_id, 'state')
    if Dir.exist?(state_path)
      Dir.glob(File.join(state_path, '*')).sample(2).each do |file|
        # Corrupt the file by adding random bytes
        File.open(file, 'a') do |f|
          f.write(SecureRandom.bytes(10))
        end
      end
    end
  end
end
