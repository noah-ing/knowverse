# frozen_string_literal: true

module Distributed
  module Testing
    # Track and analyze recovery metrics for distributed system testing
    class RecoveryMetrics
      attr_reader :metrics, :current_scenario

      # Initialize a new RecoveryMetrics tracker
      def initialize
        reset_metrics
      end

      # Reset all metrics to start fresh
      def reset_metrics
        @metrics = {
          scenarios: {},
          current_scenario: nil
        }
        @checkpoint_times = {}
        @current_scenario = nil
      end

      # Start tracking a new failure scenario
      # @param name [String] Name of the failure scenario
      # @param details [Hash] Additional details about the scenario
      def start_scenario(name, details = {})
        scenario_id = "#{Time.now.to_i}-#{name.to_s.parameterize}"
        
        @metrics[:scenarios][scenario_id] = {
          name: name,
          details: details,
          start_time: Time.now,
          checkpoints: {},
          end_time: nil,
          duration_ms: nil,
          data_consistency: nil
        }
        
        @current_scenario = scenario_id
        @checkpoint_times = {}
        
        Rails.logger.info("Started tracking metrics for scenario: #{name}")
        
        # Return the scenario ID
        scenario_id
      end

      # Record a checkpoint in the current failure scenario
      # @param name [Symbol] Name of the checkpoint (:failure_detected, :leader_election, etc.)
      # @param details [Hash] Additional details about the checkpoint
      def record_checkpoint(name, details = {})
        return unless @current_scenario
        
        now = Time.now
        @checkpoint_times[name] = now
        
        # Calculate time since start and previous checkpoint
        start_time = @metrics[:scenarios][@current_scenario][:start_time]
        time_since_start_ms = ((now - start_time) * 1000).round(2)
        
        previous_checkpoint = @metrics[:scenarios][@current_scenario][:checkpoints].keys.last
        time_since_previous_ms = if previous_checkpoint
                                 prev_time = @checkpoint_times[previous_checkpoint]
                                 ((now - prev_time) * 1000).round(2)
                               else
                                 time_since_start_ms
                               end
        
        # Record the checkpoint
        @metrics[:scenarios][@current_scenario][:checkpoints][name] = {
          time: now,
          time_since_start_ms: time_since_start_ms,
          time_since_previous_ms: time_since_previous_ms,
          details: details
        }
        
        Rails.logger.info("Recorded checkpoint '#{name}' for scenario '#{@metrics[:scenarios][@current_scenario][:name]}': +#{time_since_previous_ms}ms")
      end

      # End the current failure scenario
      # @param data_consistency [Float] Measure of data consistency after recovery (0.0-1.0)
      def end_scenario(data_consistency = nil)
        return unless @current_scenario
        
        end_time = Time.now
        start_time = @metrics[:scenarios][@current_scenario][:start_time]
        duration_ms = ((end_time - start_time) * 1000).round(2)
        
        @metrics[:scenarios][@current_scenario][:end_time] = end_time
        @metrics[:scenarios][@current_scenario][:duration_ms] = duration_ms
        @metrics[:scenarios][@current_scenario][:data_consistency] = data_consistency
        
        Rails.logger.info("Ended scenario '#{@metrics[:scenarios][@current_scenario][:name]}' after #{duration_ms}ms, data consistency: #{data_consistency || 'N/A'}")
        
        # Copy current scenario for return and clear current
        completed_scenario = @current_scenario
        @current_scenario = nil
        
        # Return the completed scenario ID
        completed_scenario
      end

      # Get summary statistics for all scenarios
      # @return [Hash] Summary statistics
      def summary_statistics
        stats = {
          total_scenarios: @metrics[:scenarios].size,
          avg_detection_time_ms: average_time_for_checkpoint(:failure_detected),
          avg_leader_election_time_ms: average_time_for_checkpoint(:leader_elected),
          avg_recovery_time_ms: average_time_for_checkpoint(:recovery_complete),
          avg_data_consistency: average_data_consistency,
          scenarios_by_type: {}
        }
        
        # Group scenarios by type
        @metrics[:scenarios].each do |_id, data|
          type = data[:details][:type] || 'unknown'
          stats[:scenarios_by_type][type] ||= {
            count: 0,
            avg_detection_time_ms: 0,
            avg_leader_election_time_ms: 0, 
            avg_recovery_time_ms: 0
          }
          
          stats[:scenarios_by_type][type][:count] += 1
        end
        
        # Calculate average times by type
        stats[:scenarios_by_type].each do |type, type_stats|
          scenarios_of_type = @metrics[:scenarios].select { |_id, data| data[:details][:type] == type }
          
          type_stats[:avg_detection_time_ms] = average_time_for_checkpoint(:failure_detected, scenarios_of_type)
          type_stats[:avg_leader_election_time_ms] = average_time_for_checkpoint(:leader_elected, scenarios_of_type)
          type_stats[:avg_recovery_time_ms] = average_time_for_checkpoint(:recovery_complete, scenarios_of_type)
        end
        
        stats
      end

      # Generate a detailed report of all scenarios
      # @return [String] Markdown-formatted report
      def generate_report
        report = "# Fault-Tolerance Test Report\n\n"
        report += "## Summary Statistics\n\n"
        
        stats = summary_statistics
        report += "- **Total Scenarios**: #{stats[:total_scenarios]}\n"
        report += "- **Average Detection Time**: #{stats[:avg_detection_time_ms].round(2)}ms\n"
        report += "- **Average Leader Election Time**: #{stats[:avg_leader_election_time_ms].round(2)}ms\n"
        report += "- **Average Recovery Time**: #{stats[:avg_recovery_time_ms].round(2)}ms\n"
        report += "- **Average Data Consistency**: #{(stats[:avg_data_consistency] * 100).round(2)}%\n\n"
        
        report += "## Scenario Types\n\n"
        stats[:scenarios_by_type].each do |type, type_stats|
          report += "### #{type.to_s.titleize}\n\n"
          report += "- **Count**: #{type_stats[:count]}\n"
          report += "- **Average Detection Time**: #{type_stats[:avg_detection_time_ms].round(2)}ms\n"
          report += "- **Average Leader Election Time**: #{type_stats[:avg_leader_election_time_ms].round(2)}ms\n"
          report += "- **Average Recovery Time**: #{type_stats[:avg_recovery_time_ms].round(2)}ms\n\n"
        end
        
        report += "## Detailed Scenarios\n\n"
        @metrics[:scenarios].each do |id, data|
          report += "### #{data[:name]}\n\n"
          report += "- **ID**: #{id}\n"
          report += "- **Type**: #{data[:details][:type] || 'N/A'}\n"
          report += "- **Total Duration**: #{data[:duration_ms]}ms\n"
          report += "- **Data Consistency**: #{data[:data_consistency] ? "#{(data[:data_consistency] * 100).round(2)}%" : 'N/A'}\n\n"
          
          if data[:details].any?
            report += "**Details**:\n\n"
            data[:details].each do |key, value|
              report += "- #{key}: #{value}\n"
            end
            report += "\n"
          end
          
          if data[:checkpoints].any?
            report += "**Checkpoints**:\n\n"
            data[:checkpoints].each do |checkpoint, cp_data|
              report += "- **#{checkpoint}**: +#{cp_data[:time_since_previous_ms]}ms (total: #{cp_data[:time_since_start_ms]}ms)\n"
            end
            report += "\n"
          end
        end
        
        report
      end

      private

      # Calculate average time for a specific checkpoint across all scenarios
      # @param checkpoint [Symbol] The checkpoint to calculate average for
      # @param scenarios [Hash] Scenarios to include (defaults to all)
      # @return [Float] Average time in milliseconds
      def average_time_for_checkpoint(checkpoint, scenarios = nil)
        scenarios ||= @metrics[:scenarios]
        
        # Filter scenarios that have this checkpoint
        scenarios_with_checkpoint = scenarios.select do |_id, data|
          data[:checkpoints] && data[:checkpoints][checkpoint]
        end
        
        return 0 if scenarios_with_checkpoint.empty?
        
        # Calculate average
        total_time = scenarios_with_checkpoint.sum do |_id, data|
          data[:checkpoints][checkpoint][:time_since_start_ms]
        end
        
        total_time / scenarios_with_checkpoint.size
      end

      # Calculate average data consistency across all scenarios
      # @return [Float] Average data consistency (0.0-1.0)
      def average_data_consistency
        scenarios_with_consistency = @metrics[:scenarios].select { |_id, data| data[:data_consistency] }
        return 0 if scenarios_with_consistency.empty?
        
        total_consistency = scenarios_with_consistency.sum { |_id, data| data[:data_consistency] }
        total_consistency / scenarios_with_consistency.size
      end
    end
  end
end
