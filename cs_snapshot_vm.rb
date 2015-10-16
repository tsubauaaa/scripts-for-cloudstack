#!/usr/bin/env ruby
require 'cloudstack_ruby_client'
require 'yaml'
require 'time'

vm_name = ARGV[0]
stop_jobid = ""
ss_jobid = ""
start_jobid = ""
vm_id = ""
gen = 3
del_ss_id = []

if ARGV.size != 1
  puts "Usage: #{$0} [virtual machine's name]"
  exit 1
end
begin
  config = YAML.load(File.read(".cloudstack/config.yml"))
  client = CloudstackRubyClient::Client.new(config['URL'], config['APIKEY'], config['SECKEY'], false)
  client.list_virtual_machines(listall: true, name: vm_name)['virtualmachine'].each { |item| vm_id = item['id'] }
  stop_jobid = client.stop_virtual_machine(id: vm_id)['jobid']
  stop_status = client.query_async_job_result(jobid: stop_jobid)['jobstatus']
  if stop_status == 0
    print ("#{Time.now}:#{vm_name} while stopping...")
    until stop_status == 1
      print (".")
      sleep 30
      stop_status = client.query_async_job_result(jobid: stop_jobid)['jobstatus']
    end
  else
    puts "#{Time.now}:#{vm_name} could not be stopped acquisition. status is #{stop_status}."
    exit 1
  end
  puts ""
  puts "#{Time.now}:#{vm_name} has been stopped."
  volumes = client.list_volumes(listall: true, virtualmachineid: vm_id)['volume']
  volumes.each do |volume|
    ss_jobid = client.create_snapshot(volumeid: volume['id'])['jobid']
    sleep 30
    ss_status = client.query_async_job_result(jobid: ss_jobid)['jobstatus']
    if ss_status == 0
      print ("#{Time.now}:Snapshot(#{volume['name']}) while backingup...")
      until ss_status == 1
        print (".")
        sleep 30
        ss_status = client.query_async_job_result(jobid: ss_jobid)['jobstatus']
      end
    elsif ss_status == 1
      puts "#{Time.now}:Snapshot(#{volume['name']}) has been completed."
      next
    else
      puts "#{Time.now}:Snapshot(#{volume['name']}) could not be started acquisition. status is #{ss_status}."
    end
    puts ""
    puts "#{Time.now}:Snapshot(#{volume['name']}) has been completed."
  end
  start_jobid = client.start_virtual_machine(id: vm_id)['jobid']
  start_status = client.query_async_job_result(jobid: start_jobid)['jobstatus']
  if start_status == 0
    print ("#{Time.now}:#{vm_name} while startingup...")
    until start_status == 1
      print (".")
      sleep 30
      start_status = client.query_async_job_result(jobid: start_jobid)['jobstatus']
    end
  else
    puts "#{Time.now}:#{vm_name} could not be started acquisition. status is #{start_status}."
    exit 1
  end
  puts ""
  puts "#{Time.now}:#{vm_name} has been started."
    sss = client.list_snapshots(listall: true, virtualmachineid: vm_id)['snapshot']
    sss.each do |ss|
      if /^#{vm_name}/ =~ ss['name']
        if Time.parse(ss['created']) < Time.now - gen*24*60*60
          del_ss_id << ss['id']
        end
      end
    end
    unless del_ss_id.size == 0
      puts "#{Time.now}:Delete because it has passed more than #{gen} days：#{del_ss_id}"
      del_ss_id.each { |id| client.delete_snapshot(id: id) }
    else
      puts "#{Time.now}:Delete snapshots is nothing."
      exit 0
    end
rescue => e
  puts "Error: exception: #{e}"
end
