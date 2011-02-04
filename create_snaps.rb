require 'rubygems'
require 'right_aws'
require 'settings'

transition_change_timeouts = [2, 5, 10, 30, 60] # Total of 107 seconds, or just about 1.75 minutes
all_stopped = false

Settings.get_credentials()

ec2 = Rightscale::Ec2.new(Settings.aws_access_key_id, Settings.aws_secret_access_key)

instances = ec2.describe_instances()

instances_to_snapshot = []

instances.each do |instance|
  if instance[:aws_state] == "running"
    instances_to_snapshot += [instance]
  end
end

instances_to_snapshot.delete_if { |instance| !Settings.instances.include?(instance[:aws_instance_id]) } unless Settings.instances == []

ids = instances_to_snapshot.collect { |i| i[:aws_instance_id] }

if ids != []

  puts "About to stop the following AWS EC2 instances..."
  ids.each { |id| puts id }

  ec2.stop_instances(ids)

  # Wait for all of them to be stopped..
  transition_change_timeouts.each do |timeout|
    all_stopped = (ec2.describe_instances(ids).collect { |i| i[:aws_state] == "stopped" }.count == ids.count)
    if all_stopped
      break
    else
      puts "Waiting (#{timeout})s for instances to stop..."
      sleep(timeout)
    end
  end

  if !all_stopped
    # TODO: What do we want to do here?
  end
else
  puts "No running instances were found to create snapshots of.  Double check your settings."
end