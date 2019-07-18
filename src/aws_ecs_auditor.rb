require 'aws-sdk-autoscaling'
require 'aws-sdk-ecs'
require 'aws-sdk-applicationautoscaling'

NEW_LINE = "\n"

class AwsEcsAuditor

  def initialize(region, cluster_name)
    @region = region
    @cluster_name = cluster_name
    @number_of_tasks_per_ec2_instance = 8
    @asg_client = Aws::AutoScaling::Client.new(region: region)
    @ecs_client = Aws::ECS::Client.new(region: region)
    @aas_client = Aws::ApplicationAutoScaling::Client.new(region: region)
  end

  def list_container_instances
    @list_container_instances ||= @ecs_client.list_container_instances(
      cluster: @cluster_name,
      max_results: 1,
      status: 'ACTIVE'
    )[:container_instance_arns][0].split('/')[1]
  end

  def ecs_instance_id
    @ecs_instance_id ||= @ecs_client.describe_container_instances(
      cluster: @cluster_name,
      container_instances: [list_container_instances]
    )[:container_instances][0][:ec2_instance_id]
  end

  def autoscaling_group_name
    @autoscaling_group_name ||= @asg_client.describe_auto_scaling_instances(
      instance_ids: [ecs_instance_id]
    )[:auto_scaling_instances][0][:auto_scaling_group_name]
  end


  def describe_autoscaling_group
    @describe_autoscaling_group ||= @asg_client.describe_auto_scaling_groups({
      auto_scaling_group_names: [autoscaling_group_name],
      max_records: 1
    })[:auto_scaling_groups][0]
  end

  def list_services
    @list_services ||= @ecs_client.list_services({cluster: @cluster_name, max_results: 100, launch_type: 'EC2'})[:service_arns].map{|s| s.split('/')[1]}
  end

  def describe_services
    @describe_services ||= []
    return @describe_services unless @describe_services.empty?

    list_services.each_slice(3) do |slice|
      @describe_services.push @ecs_client.describe_services({cluster: @cluster_name, services: slice})[:services]
    end

    @describe_services.flatten!
  end

  def total_min_desired_tasks
    @total_min_desired_tasks ||= describe_services.map(&:desired_count).inject(0, :+)
  end

  def total_running_desired_tasks
    @total_running_desired_tasks ||= describe_services.map(&:running_count).inject(0, :+)
  end

  def max_number_of_running_tasks
    services = list_services.map { |s| "service/#{@cluster_name}/#{s}" }
    @max_number_of_running_tasks ||= @aas_client.describe_scalable_targets(
      service_namespace: 'ecs',
      resource_ids: services
    )[:scalable_targets].map(&:max_capacity).inject(0, :+)
  end

  def report
    puts '----Basic ECS Info----'
    puts 'ECS Cluster Region: ' + @region
    puts 'ECS Cluster Name: ' + @cluster_name

    puts NEW_LINE

    puts '----Gathered Metrics----'
    puts 'Number of ECS Services in this Cluster: ' + list_services.count.to_s
    puts 'Number of ECS Tasks per ECS Host: ' + @number_of_tasks_per_ec2_instance.to_s

    puts NEW_LINE

    puts 'Minimum tasks required across all services: ' + total_min_desired_tasks.to_s
    puts 'Number of running tasks across all services: ' + total_running_desired_tasks.to_s
    puts 'Maximum tasks allowable across all services: ' + max_number_of_running_tasks.to_s

    puts NEW_LINE
    puts 'Current value for Minimum number of EC2 Instances: ' + describe_autoscaling_group[:min_size].to_s
    puts 'Current value for Running number of EC2 Instances: ' + describe_autoscaling_group[:desired_capacity].to_s
    puts 'Current value for Maximum number of EC2 Instances: ' + describe_autoscaling_group[:max_size].to_s

    puts NEW_LINE

    puts '----Analysis----'
    new_min_instance_count = (total_min_desired_tasks / @number_of_tasks_per_ec2_instance) + (list_services.count / @number_of_tasks_per_ec2_instance)
    current_number_of_instances_required = (total_running_desired_tasks / @number_of_tasks_per_ec2_instance) + (list_services.count / @number_of_tasks_per_ec2_instance)
    
    puts 'Number of instances needed for current number of running tasks: ' + current_number_of_instances_required.to_s + ' (including room to scale by 1 task per servcie)'
    puts 'We should set the minimum number of EC2 Hosts for the cluster from ' + describe_autoscaling_group[:min_size].to_s + ' to ' + new_min_instance_count.to_s + ' (including room to scale by 1 task per servcie)'
    puts 'We should set the maximum number of EC2 Hosts for the cluster from ' + describe_autoscaling_group[:max_size].to_s + ' to ' + (max_number_of_running_tasks / @number_of_tasks_per_ec2_instance).to_s

  end
end

auditor = AwsEcsAuditor.new(ENV['AWS_REGION'], ENV['CLUSTER_NAME'])
auditor.report
