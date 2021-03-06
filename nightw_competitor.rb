#!/usr/bin/env ruby

# The program is written for the scaling contest of Prezi.com which can
# be found here: http://prezi.com/scale/
#
# VERSION: state machine approach aka. version 2
#
# The shortest summary is that the program is a scheduler which tracks
# every incoming job and tries to predict the need in the near feature
# form the current utilization

# Author::    Pal David Gergely  (mailto:nightw17@gmail.com), Andras Ivanyi (mailto:andras.ivanyi@gmail.com)
# Copyright:: Copyright (c) 2013 Pal David Gergely
# License::   Apache License, Version 2.0

########################################################################
###################################### Constants #######################
########################################################################

# This is the number of VMs in every queue we always want to run as
# idle to handle possible incoming spikes
FIX_NUMBER_OF_VMS = 40

# This is the MINIMUM treshold of how many percent of the VMs MUST be
# free at any given time in any given queue
# (If there is LESS than that percent of VMs are free, then we START new
# ones to be at least that many free VMs)
MIN_IDLE_VM_PERCENT = 0.4

# This is the MAXIMUM treshold of how many percent of the VMs CAN be
# free at any given time in any given queue
# (If there is MORE than that percent of VMs are free, then we STOP them
# to be only that many free)
MAX_IDLE_VM_PERCENT = 0.7

# This is the time needed for a VM to start in seconds
VM_START_TIME = 2 * 60

# The available queues (constant)
QUEUES = %w[ export url general ]

########################################################################
###################################### Checks at start time ############
########################################################################

# We check the Ruby version and print a warning if it's not 1.9.x
if !RUBY_VERSION.start_with?('1.9')
	$stderr.puts 'WARNING: The code was tested only on Ruby 1.9!!!' 
end

# Check for stdin input availability
if $stdin.tty?
	puts 'There were no input from stdin!'
	exit 1
end

########################################################################
###################################### Classes #########################
########################################################################

# This class represents a Job with all of available information form
# input and also some computed information. These are the following:
# * date as string
# * time as string
# * uid
# * queue
# * length
# * date and time as Time object
# * start time of the job when it got started to executing on a VM
class Job
	# These attributes can only be read
	attr_reader :date
	attr_reader :time
	attr_reader :date_time
	attr_reader :uid
	attr_reader :queue
	attr_reader :length
	
	# We can only set the attributes at start time and all of them is
	# mandatory
	def initialize(date, time, uid, queue, length)
		@date = date
		@time = time
		@uid = uid
		@queue = queue
		@length = length
		@date_time = parse_date_and_time(date, time)
		@start_time = nil
	end
	
	# The only attribute which can be set later is that when the job
	# was started
	def start_time=(value)
		if value.kind_of?(Time)
			@start_time = value
		else
			raise "Wanted a Time object, found: #{value.inspect}"
		end
	end
	
	# This attribute can also be read
	def start_time
		return @start_time
	end
	
	# This function tells that the job is running currently or not
	def running?(date, time)
		return running_date_time?(parse_date_and_time(date, time))
	end
	
	# This function tells that the job is running currently or not
	def running_date_time?(date_time)
		if !@start_time.nil? && date_time - (@start_time + length.to_f) < 0
			return true
		else
			return false
		end
	end
	
	# This function return the time when the request will be finished
	def finishes_at()
		return @start_time + length.to_f
	end
end

# Class for managing running VMs for queues
class QueueManager
	# We initilize the variables and also start the fixed number of VMs
	# for every queue. The date and time parameter is mandatory
	def initialize(date, time)
		@start_date_time = parse_date_and_time(date, time)
		@queues = Hash.new
		QUEUES.each do |q|
			@queues[q] = Array.new
			FIX_NUMBER_OF_VMS.times do
				start_vm(date, time, q)
			end
		end
	end

	# To start a VM in a given queue
	def start_vm(date, time, queue)
		if QUEUES.include?(queue)
			vm = Vm.new(date, time)
			vm.queue = queue
			@queues[queue].push(vm)
			vm.start
		else
			raise "Invalid queue: #{queue}"
		end
	end
	
	# To stop a VM in a given queue
	def stop_vm_date_time(date_time, queue, count)
		# First sanity check
		if QUEUES.include?(queue)
			# We look for the VMs which has the least mintues left in the
			# current hour
			vms_to_stop = Hash.new
			for i in 0..9
				vms_to_stop[i] = Array.new
			end
			# We check how many VMs we can stop before reacing the
			# minimum (FIX_NUMBER_OF_VMS)
			stoppable_vms_count = @queues[queue].length - FIX_NUMBER_OF_VMS
			if stoppable_vms_count <= 0
				return
			elsif stoppable_vms_count < count
				count = stoppable_vms_count
			end
			@queues[queue].each do |vm|
				current_time_left = vm.time_left_in_hour_date_time(date_time)
				if current_time_left < 10
					vms_to_stop[current_time_left.to_i].push vm
				end
			end
			vms_stopped = 0
			for i in 0..9
				vms_to_stop[i].each do |vm|
					vm.stop(date_time.strftime("%Y-%m-%d"), date_time.strftime("%H:%M:%S"))
#					$stderr.puts "#{date_time.strftime('%Y-%m-%d')} #{date_time.strftime('%H:%M:%S')} stopped: #{vm.inspect}, count before: #{@queues[queue].size}"
					@queues[queue].delete(vm)
					vms_stopped += 1
					if vms_stopped >= count
						return
					end
				end
			end
		else
			raise "Invalid queue: #{queue}"
		end
	end
	
	# To stop a VM in a given queue
	def stop_vm(date, time, queue, count)
		stop_vm_date_time(parse_date_and_time(date, time), queue, count)
	end
	
	# To stop all the VMs in every queue
	# Should only be used when the program is exiting
	def stop_all_vms(date, time)
		QUEUES.each do |q|
			@queues[q].each do |vm|
				vm.stop(date, time)
				@queues[q].delete(vm)
			end
		end
	end
	
	# This function is for scheduling an incoming request
	# That means assigning it to a VM and adjusting the job's VM pool
	# size if neccesary
	# It's input paramaters are a job's parts in string format
	def schedule_request_with_parts(date, time, uid, queue, length, write_log=false, log_file=nil)
		job = Job.new(date, time, uid, queue, length)
		schedule_request(job, write_log, log_file)
	end
	
	# This function is for scheduling an incoming request
	# That means assigning it to a VM and adjusting the job's VM pool
	# size if neccesary
	# It's input parameter is a Job object
	def schedule_request(job, write_log=false, log_file=nil)
		if job..kind_of?(Job)
			# We set the initial states for the job scheduling and
			# accounting
			found = false
			real_free_vms = free_vms_without_start_time = 0
			# First we go over all the VMs in the given queue
			@queues[job.queue].each do |vm|
				# We get the time when that VM will be available
				vm_free_at = vm.free_at_date_time(job.date_time)
				# We determine from the previous result that the vm is
				# free NOW or not and if it's free then we add it to the
				# real_free_vms counter
				if vm_free_at == job.date_time && found
					real_free_vms += 1
				end
				# We also count the time when the VM will be available not
				# counting the startup time (for scheduling purposes)
				free_vms_without_start_time += 1 if vm.free_date_time?(job.date_time, true)
				# Now we assign the current job to the first free VM (or
				# the first VM which will be free in 5 secs)
				if !found && vm_free_at < job.date_time + 5
					job.start_time = vm_free_at
					vm.job = job
					found = true
				end
			end
			# We did not found any VM even with 5 secs "wait" so we
			# check for being in the first 24 hours when there is no
			# penalty for being unable to schedule a job correctly or
			# we're over it
			if !found
				if job.date_time > @start_date_time + 24 * 60 * 60
					raise "There was no available VM for the request: #{job.uid}"
				else
#					$stderr.puts "WARNING: there is no free VM for job #{job.uid} at: #{job.date} #{job.time} (but we're in the first 24 hours)"
				end
			end
			# Now we start or stop VMs if it is necessary according the
			# previously counted utilization 
#			$stderr.puts "There is #{free_vms_without_start_time}/#{real_free_vms}/#{@queues[job.queue].size} VMs free in #{job.queue} (before VM pool management)"
			# First we stop VMs if the utiliziation is below a minimum
			# treshold
			if free_vms_without_start_time.to_f / @queues[job.queue].size > MAX_IDLE_VM_PERCENT
				# Now we stop VMs to rise the utilization to the minimum
				# treshold but we cannot have fewer VMs than the
				# FIX_NUMBER_OF_VMS value
				number_of_vms_to_stop = (free_vms_without_start_time - @queues[job.queue].size * MAX_IDLE_VM_PERCENT).ceil
				if free_vms_without_start_time - number_of_vms_to_stop > FIX_NUMBER_OF_VMS
					stop_vm_date_time(job.date_time, job.queue, number_of_vms_to_stop)
				end
			end
			# Second we check that if there is less then
			# FIX_NUMBER_OF_VMS are free, then we raise the number of
			# VMs to be at least that many
			if FIX_NUMBER_OF_VMS - free_vms_without_start_time > 0
				(FIX_NUMBER_OF_VMS - free_vms_without_start_time).times do
					start_vm(job.date, job.time, job.queue)
				end
				free_vms_without_start_time = FIX_NUMBER_OF_VMS
			end
			# The we check that if there is still fewer VMs are free
			# then a minimum treshold of the full VM number then we
			# start some to be at least that many free
			if free_vms_without_start_time.to_f / @queues[job.queue].size < MIN_IDLE_VM_PERCENT
				(@queues[job.queue].size * MIN_IDLE_VM_PERCENT - free_vms_without_start_time).ceil.times do
					start_vm(job.date, job.time, job.queue)
				end
			end
			if write_log
				@@log_file.puts "#{job.date} #{job.time} #{job.queue} #{@queues[job.queue].length} #{real_free_vms} #{(@queues[job.queue].size * MIN_IDLE_VM_PERCENT).to_i}"
			end
		else
			raise "Job type was needed and got #{job.inspect}"
		end
	end
end

# Class is for storing and handling VMs
# Can store creation time and give info about how many minutes left
# in the current hour. Also stores the queue of the VM and the currently
# running job
class Vm
	# attr_writer for queue attribute with sanity check
	def queue=(value)
		if QUEUES.include?(value)
			@queue = value unless !QUEUES.include?(value)
		else
			raise "Invalid queue: #{queue}"
		end
	end
	
	# The queue attribute can also be read
	attr_reader :queue
	# The creation time is only readable, only initialize can set it
	attr_reader :creation_time
	# The currently running job in the VM if there is any
	attr_accessor :job
	
	def initialize(date=nil, time=nil)
		if date.nil? || time.nil?
			raise "Cannot initialize VM without creation time!"
		end
		@creation_time = parse_date_and_time(date, time)
	end
	
	# Returns the minutes left for the current hour for decision making
	# about the VM for stopping before billing period ends
	def time_left_in_hour(date, time)
		return time_left_in_hour_date_time(parse_date_and_time(date, time))
	end
	
	# Returns the minutes left for the current hour for decision making
	# about the VM for stopping before billing period ends
	def time_left_in_hour_date_time(date_time)
		return 60 - (((date_time - @creation_time) % 3600) / 60)
	end
	
	# Write out that the VM has been stopped
	def stop(date, time)
		puts "#{date} #{time} terminate #{@queue}"
	end

	# Write out that the VM has been started
	def start()
		puts "#{@creation_time.strftime("%Y-%m-%d %H:%M:%S")} launch #{@queue}"
	end
	
	# Returns true is the VM currently is running no jobs OR a previous
	# job has been finished
	def free?(date, time, ignore_start_time=false)
		return free_date_time?(parse_date_and_time(date, time), ignore_start_time)
	end
	
	# Returns true is the VM currently is running no jobs OR a previous
	# job has been finished
	def free_date_time?(date_time, ignore_start_time=false)
		if !@job.nil?
			if @job.running_date_time?(date_time)
				return false
			else
				@job = nil
				return true
			end
		else
			# if we ignore start_time then we're free
			if ignore_start_time
				return true
			else
				# only free if the VM has been started since creation
				if date_time > @creation_time + VM_START_TIME
					return true
				else
					return false
				end
			end
		end
	end
	
	# Returns the time when the VM will be available to run jobs. If the
	# VM is not running any jobs, then it returns the input date and
	# time
	def free_at(date, time)
		return free_at_date_time(parse_date_and_time(date, time))
	end
	
	# Returns the time when the VM will be available to run jobs. If the
	# VM is not running any jobs, then it returns the input date and
	# time
	def free_at_date_time(date_time)
		if !@job.nil?
			if @job.running_date_time?(date_time)
				return @job.finishes_at
			else
				@job = nil
				return date_time
			end
		else
			# We return the bigger from the current time and the
			# creation time plus start time
			return [date_time, @creation_time + VM_START_TIME].max
		end
	end
end

########################################################################
###################################### Utility functions ###############
########################################################################

# Processes a date and a time string to split them into year, month,
# day, hours, minutes, seconds
#
# Return Time object from the given date and time Strings
def parse_date_and_time(date, time)
	year = month = day = hours = minutes = seconds = nil
	date.split("-").each_with_index { |part, index|
		case index
			when 0
				year = part
			when 1
				month = part
			when 2
				day = part
		end
	}
	time.split(":").each_with_index { |part, index|
		case index
			when 0
				hours = part
			when 1
				minutes = part
			when 2
				seconds = part
		end
	}
	return Time.new(year.to_i, month.to_i, day.to_i, hours.to_i, minutes.to_i, seconds.to_i)
end

# Processes a line string by splitting it to parts to extract the
# information from it
#
# Return multivalue in the following order:
# * date (The year, month, day part of the date)
# * time (The hour, minute, seconds part of the date)
# * uid of the job
# * queue
# * length of the job in seconds
def process_line(line)
	# initialize variables to avoid nil exceptions
	date = time = uid = queue = length = nil
	
	# line format is the following:
	# 2013-03-01 00:00:27 713b860d-0b59-4475-8016-da84c0628032 export 10.999
	line.split(' ').each_with_index { |part, index|
		case index
			when 0
				date = part
			when 1
				time = part
			when 2
				uid = part
			when 3
				queue = part
			when 4
				length = part
		end
    }
    return date, time, uid, queue, length
end

# Prints a previously read job from parts back to stdout in the needed
# format
def puts_job_back_to_stdout_from_parts(date, time, uid, queue, length)
	puts "#{date} #{time} #{uid} #{queue} #{length}"
end

# Prints a previously read job from Job object back to stdout in the
# needed format
def puts_job_back_to_stdout(job)
	puts "#{job.date} #{job.time} #{job.uid} #{job.queue} #{job.length}"
end

########################################################################
###################################### Main program ####################
########################################################################

# We check that we have given a log file in the command line or not
if ARGV.length > 0
	@@log_file = File.open(ARGV[0], 'w')
	ARGV.shift
else
	@@log_file = nil
end

# We read the first line and process it first to get the start date
firstline = ARGF.readline
date, time, uid, queue, length = process_line firstline 

# Now we initialize the QueueManager object and the first VMs in it
@@queue_manager = QueueManager.new(date, time)

# Now we give the job to the queue manager
@@queue_manager.schedule_request_with_parts(date, time, uid, queue, length)

# Now we print the first line
puts_job_back_to_stdout_from_parts date, time, uid, queue, length

# Now we process the reamining lines line by line
ARGF.each_with_index do |line, index|
	date, time, uid, queue, length = process_line line
	begin
		# Now we process the job (with logging information wirte if a
		# log file was given in the command line arguments
		if !@@log_file.nil?
			@@queue_manager.schedule_request_with_parts(date, time, uid, queue, length, true, @@log_file)
		else
			@@queue_manager.schedule_request_with_parts(date, time, uid, queue, length)
		end
		puts_job_back_to_stdout_from_parts date, time, uid, queue, length
		$stdout.flush
    rescue Errno::EPIPE
#		$stderr.puts "#{date} #{time}"
		if !@@log_file.nil?
			@@log_file.close
		end
		exit 1
	rescue SignalException
		if !@@log_file.nil?
			@@log_file.close
		end
		exit 0
	end
end

# And now we terminate all the VMs, because we finished processing the
# input
@@queue_manager.stop_all_vms(date, time)

if !@@log_file.nil?
	@@log_file.close
end

