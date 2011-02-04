require 'rubygems'
require 'right_aws'
require 'settings'

transition_change_timeouts  = [5, 10, 30, 60, 90, 120] # Total of 315 seconds, or just over 5 minutes
all_stopped                 = false
all_started                 = false
volumes_snapshotted         = 0
startTs                     = Time.now
startDate                   = startTs.strftime("%Y%m%d%H%M%S")

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
    all_stopped = (ec2.describe_instances(ids).select { |i| i[:aws_state] == "stopped" }.count == ids.count)
    if all_stopped
      break
    else
      puts "Waiting (#{timeout})s for instances to stop..."
      sleep(timeout)
    end
  end

  if !all_stopped
    # TODO: What do we want to do here?  After all is said and done, we really need for the servers to be started again
    # even if a snapshot doesn't get taken.
    puts "Even after all the waiting, not all instances were stopped, this is critical.. I should notify someone..."
  else
    puts "All instances are stopped, proceeding with snapshots..."
    instances_to_snapshot.each do |instance|
      instance[:block_device_mappings].each do |mapping|
        puts "Creating snapshot of volume #{mapping[:ebs_volume_id]} from instance #{instance[:aws_instance_id]}"
        volumes_snapshotted += 1
        ec2.create_snapshot(mapping[:ebs_volume_id], "aws_snapshotter automated snapshot of #{mapping[:ebs_volume_id]} at #{startDate}")

        # TODO: Prune old snapshots
      end
    end
  end

  ec2.start_instances(ids)

  # Wait for all of them to be stopped..
  transition_change_timeouts.each do |timeout|
    all_started = (ec2.describe_instances(ids).select { |i| i[:aws_state] == "running" }.count == ids.count)
    if all_started
      break
    else
      puts "Waiting (#{timeout})s for instances to start..."
      sleep(timeout)
    end
  end

  if !all_started
    puts "Even after all the waiting, not all instances were started, this is critical.. I should notify someone..."
  else
    puts "Finished creating #{volumes_snapshotted} snapshots from #{ids.count} instances in #{Time.now.to_i - startTs.to_i} seconds.  You've been snapshotted!"
  end

else
  puts "No running instances were found to create snapshots of.  Double check your settings."
end