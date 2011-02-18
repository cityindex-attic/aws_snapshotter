require 'rubygems'
require 'right_aws'
require 'settings'
require 'enumerator'

transition_change_timeouts  = [5, 10, 30, 60, 90, 120] # Total of 315 seconds, or just over 5 minutes
timeout_sum                 = 0
all_stopped                 = false
all_started                 = false
volumes_snapshotted         = 0
startTs                     = Time.now
startDate                   = startTs.strftime("%Y%m%d%H%M%S")
$messages                   = []

def log(message)
  puts message
  $messages << message
end

def format_messages_for_sns
  retVal = ''
  $messages.each {|message| retVal += message + "
"}
  retVal
end

transition_change_timeouts.each{|t| timeout_sum += t}

Settings.get_settings()

ec2 = Rightscale::Ec2.new(Settings.aws_access_key_id, Settings.aws_secret_access_key)
sns = Rightscale::SnsInterface.new(Settings.aws_access_key_id, Settings.aws_secret_access_key)
sns_configured = false

if Settings.notify_by_sns
  if Settings.sns_topic_id.right_blank? && Settings.create_sns
    topic_arn = sns.create_topic('AWSSnapshotterEvents')
    if topic_arn
      lines = File.readlines('./aws_snapshotter_settings.rb')
      File.open('./aws_snapshotter_settings.rb', 'w') do |f|
        lines.each do |line|
          line.gsub!(/Settings::sns_topic_id(\s*)=.*$/,'Settings::sns_topic_id\1=' +" '#{topic_arn}'")
          f.puts(line)
        end
      end

      Settings.sns_subscribers.each do |subscriber|
        sns.subscribe(topic_arn, 'email', subscriber)
      end

      require './aws_snapshotter_settings.rb'
    end
  end

  sns_configured = sns.list_topics().collect{|topic| topic[:arn]}.include?(Settings.sns_topic_id)
end

instances = ec2.describe_instances()

instances_to_snapshot = []

instances.each do |instance|
  if instance[:aws_state] == "running"
    instances_to_snapshot += [instance]
  end
end

instances_to_snapshot.delete_if { |instance| !Settings.instances.include?(instance[:aws_instance_id]) } unless Settings.instances == []

ids = instances_to_snapshot.collect { |i| i[:aws_instance_id] }

ips = instances_to_snapshot.to_enum(:each_with_index).collect { |ip,idx| {"PublicIp.#{idx}" => ip[:ip_address]} }

eips = ec2.describe_addresses(ips)

if ids != []
  log "About to stop the following AWS EC2 instances..."
  ids.each { |id| log "AWS Instance ID: #{id}" }

  ec2.stop_instances(ids)

  # Wait for all of them to be stopped..
  transition_change_timeouts.each do |timeout|
    all_stopped = (ec2.describe_instances(ids).select { |i| i[:aws_state] == "stopped" }.count == ids.count)
    if all_stopped
      break
    else
      log "Waiting (#{timeout})s for instances to stop..."
      sleep(timeout)
    end
  end

  if !all_stopped
    # TODO: What do we want to do here?  After all is said and done, we really need for the servers to be started again
    # even if a snapshot doesn't get taken.
    log "After waiting #{timeout_sum} for #{instances_to_snapshot.count} instances to stop, some instances remain running"
    sns.publish(Settings.sns_topic_id, format_messages_for_sns,
                "Instance Stop Failed!") if sns_configured
  else
    log "All instances are stopped, proceeding with snapshots..."
    instances_to_snapshot.each do |instance|
      instance[:block_device_mappings].each do |mapping|
        ebsvol = ec2.describe_tags(:filters => { 'resource-id' => mapping[:ebs_volume_id] })
        name_tag = 'Unknown'
        ebsvol.each do |tag|
          name_tag = tag[:value] if tag[:key].downcase == 'name'
        end
        snap_retval = ec2.create_snapshot(mapping[:ebs_volume_id], "aws_snapshotter automated snapshot of #{mapping[:ebs_volume_id]} --{#{name_tag}}-- at #{startDate}")
        log "Created snapshot #{snap_retval[:aws_id]} of volume #{mapping[:ebs_volume_id]} --{#{name_tag}}-- from instance #{instance[:aws_instance_id]}"
        volumes_snapshotted += 1

        snapshots = ec2.describe_snapshots(:filters => {'volume-id' => mapping[:ebs_volume_id]}).sort {|a,b| a[:aws_started_at] <=> b[:aws_started_at]}

        if snapshots.count > Settings.snapshots_to_keep
          num_to_delete = snapshots.count - Settings.snapshots_to_keep
          snapshots.each_with_index do |snapshot,idx|
            if idx == (num_to_delete-1) then break end
            log "Deleting AWS Snapshot ID: #{snapshot[:aws_id]}"
            ec2.delete_snapshot(snapshot[:aws_id])
          end
        end
      end
    end
  end

  ec2.start_instances(ids)

  # Wait for all of them to be started...
  transition_change_timeouts.each do |timeout|
    all_started = (ec2.describe_instances(ids).select { |i| i[:aws_state] == "running" }.count == ids.count)
    if all_started
      break
    else
      log "Waiting (#{timeout})s for instances to start..."
      sleep(timeout)
    end
  end

  if !all_started
    log "After waiting #{timeout_sum} to restart #{instances_to_snapshot.count} instances, some were still not running!"
    sns.publish(Settings.sns_topic_id,
                format_messages_for_sns,
                "Instance Restart Failed!") if sns_configured
  else
    # Reassign any EIPS
    if eips.count > 0
      eips.each do |eip|
        ec2.associate_address(eip[:instance_id], eip[:public_ip])
        log "Reassociating EIP #{eip[:public_ip]} with instance #{eip[:instance_id]}"
      end
    end

    log "Finished creating #{volumes_snapshotted} snapshots from #{ids.count} instances in #{Time.now.to_i - startTs.to_i} seconds.  You've been snapshotted!"
    sns.publish(Settings.sns_topic_id, format_messages_for_sns, "Snapshots Completed!") if sns_configured
  end

else
  log "No running instances were found to create snapshots of.  Double check your settings."
  sns.publish(Settings.sns_topic_id, format_messages_for_sns, "AWS Snapshotter Invalid Configuration") if sns_configured
end