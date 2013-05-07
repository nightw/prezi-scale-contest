#!/usr/bin/env ruby

# The program is written for the scaling contest of Prezi.com which can
# be found here: http://prezi.com/scale/
#
# The basic concept of the algorithm is the following:
# * There are always a (comaparatively low) fixed number of virtual
#   machines available as an idle pool to process the incoming
#   requests in the near future
# * There is a second proportional component which is computed from the
#   highest spike of the last 24 hours
# * There are also two distinct trend analizers for a time windows of
#   the past hour and 24 hours to try to guess the amount of VMs needed
#   for the next 60 minutes
# * The pool of running VMs is consisted of sum of the above two
#   proportional parts and from the predicted number from the shorter
#   trend analyzed
# * And another rule is that we only stop VMs when the following
#   conditions are met:
#   * The VMs has maximum 5 minutes left for it's current hour
#   * The short trend of requests is not rising
#   * The number of the remaining VMs does not fall below the sum of the
#     two proportional parts
#
# Or the shortest summary is that the program tries to implement 3
# distinct and a bit tricky PD controller which tries to use the
# requests data as input to control the output which is the number of
# VMs running.

# Author::    Pal David Gergely  (mailto:nightw17@gmail.com), Andras Ivanyi (mailto:andras.ivanyi@gmail.com)
# Copyright:: Copyright (c) 2013 Pal David Gergely
# License::   Apache License, Version 2.0

# This is the number of VMs in every queue we always want to run as
# idle to handle possible incoming spikes
PROPORTIONAL_NUMBER_OF_VMS = 5

# The available queues (constant)
QUEUES = %w[ export url general ]

# We set up queue arrays to push VMs into them
@@export_q = Array.new
@@url_q = Array.new
@@general_q = Array.new

# We check the Ruby version and print a warning if it's not 1.9.x
if !RUBY_VERSION.start_with?('1.9')
	$stderr.puts 'WARNING: The code was tested only on Ruby 1.9!!!' 
end

# Check for stdin input availability
if $stdin.tty?
	puts 'There were no input from stdin!'
	exit 1
end

# Class is for storing and handling VMs
# Can store creation time and give info about how many minutes left
# in the current hour. Also stores the queue of the VM
class Vm
	# attr_writer for queue attribute with sanity check
	def queue=(value)
		@queue = value unless !QUEUES.include?(value)
	end
	
	# The queue attribute can also be read
	attr_reader :queue
	# The creation time is only readable, only initialize can set it
	attr_reader :creation_time
	
	def initialize(date=nil, time=nil)
		if date.nil? || time.nil?
			raise "Cannot initialize VM without creation time!"
		end
		@creation_time = parse_date_and_time(date, time)
	end
	
	# Returns the minutes left for the current hour for decision making
	# about the VM for stopping before billing period ends
	def time_left_in_hour(date, time)
		return 60 - (((parse_date_and_time(date, time) - @creation_time) % 3600) / 60)
	end
	
	def stop(date, time)
		eval "@@#{@queue}_q.delete self"
		puts "#{date} #{time} terminate #{@queue}"
	end
end

# This is the trend analyzer
# It stores *per queue* the sum of incoming request for every minute
# for the last 24 hours
class Trend
	# That is the time window in minutes to store data for
	MINUTES_TO_STORE = 60 * 24

	def initialize(date=nil, time=nil)
		if date.nil? || time.nil?
			raise "Cannot initialize Trend class without creation time!"
		end
		@last_req = @starttime = parse_date_and_time(date, time)
		@reqs_sum = Hash.new
		@reqs_num = Hash.new
		@last_shift = Hash.new
		# We initialize the Hash variables to defaults
		QUEUES.each do |queue|
			@last_shift[queue] = MINUTES_TO_STORE - 1
			@reqs_sum[queue] = Array.new
			@reqs_num[queue] = Array.new
		end
	end
	
	def add_req(date, time, queue, length, uid)
		# We sanity check the queue
		if !QUEUES.include?(queue)
			raise "Invalid queue for adding request!"
		end
		datetime = parse_date_and_time(date, time)
		# We sanity check the time diff since the last request
		if datetime - @last_req > 60*30
			$stderr.puts "Input data inconsistency: Last request and current request has was more the 30 minutes difference around uid: #{uid}"
			return
		end
		number_of_minutes_since_start = ((datetime - @starttime) / 60.to_f).to_i
		if number_of_minutes_since_start < MINUTES_TO_STORE
			# We're within the first day, so we just add our value to the array
			if @reqs_sum[queue][number_of_minutes_since_start].nil?
				@reqs_sum[queue][number_of_minutes_since_start] = length.to_f
				@reqs_num[queue][number_of_minutes_since_start] = 1
			else
				@reqs_sum[queue][number_of_minutes_since_start] += length.to_f
				@reqs_num[queue][number_of_minutes_since_start] = @reqs_num[queue][number_of_minutes_since_start] + 1
			end
			#puts "#{queue}: #{number_of_minutes_since_start}th min, #{@reqs_num[queue][number_of_minutes_since_start]} pc, #{@reqs_sum[queue][number_of_minutes_since_start]} sum length"
		else
			# we are over a 24 hour period, so we only write the last
			# element and shift the array when the minute changes
			if @last_shift[queue] < number_of_minutes_since_start
				@reqs_sum[queue].shift(number_of_minutes_since_start - @last_shift[queue])
				@reqs_sum[queue][MINUTES_TO_STORE - 1] = length.to_f
				@reqs_num[queue][MINUTES_TO_STORE - 1] = 1
				@last_shift[queue] = number_of_minutes_since_start
			else
				@reqs_sum[queue][MINUTES_TO_STORE - 1] += length.to_f
				@reqs_num[queue][MINUTES_TO_STORE - 1] = @reqs_num[queue][MINUTES_TO_STORE - 1] + 1
			end
			#puts "#{queue}: #{MINUTES_TO_STORE - 1}th min, #{@reqs_num[queue][MINUTES_TO_STORE - 1]} pc, #{@reqs_sum[queue][MINUTES_TO_STORE - 1]} sum length"
		end
		@last_req = datetime
	end
	
	def dump_info		
		@reqs_sum.each do |req_sum_name, req_sum_value|
			req_sum_value.each_with_index do |sum_length, index|
				puts "#{req_sum_name}: #{index}: #{@reqs_num[req_sum_name][index]} pc, #{sum_length} sum length"
			end
		end
	end
	
	# This function computes the trend of the last 5 mintes by queue
	# The trend in this case is a number which corresponds to the
	# growing or shrinking of incoming request
	def short_trend(queue)
		if @reqs_sum[queue].length - 5 < 1
			return 0
		end
		last_five_mins_sum = @reqs_sum[queue].drop(@reqs_sum[queue].length - 5)
		last_five_mins_sum.compact!
		diffs = Array.new
		for i in 0..(last_five_mins_sum.length - 2) do
			diffs[i] = last_five_mins_sum[i + 1] - last_five_mins_sum[i]
		end
		# We also need the second level diffs
		diffs2 = Array.new
		for i in 0..(diffs.length - 2) do
			diffs2[i] = diffs[i + 1] - diffs[i]
		end
		# And we need these diffs in a single number
		sum_diff = 0
		diffs.each do |diff|
			sum_diff += diff
		end
		diffs2.each do |diff2|
			# And we need the second level diff (acceleration) with more
			# weight
			sum_diff += diff2 * 2
		end
		return sum_diff
	end
	
	# This function computes the trend of the last 24 hours and gives
	# back the biggest spike of 4 minute windows in those hours in one
	# Fixnum
	def long_trend(queue)
		# If we're in the first 12 hours then we do nothing
		if @reqs_sum[queue].length  < 12 * 60
			return 0
		end
		reqs_sum_without_nils = @reqs_sum[queue].compact
		biggest_need_in_4_mins = reqs_sum_without_nils[0] +
			reqs_sum_without_nils[1] +
			reqs_sum_without_nils[2] +
			reqs_sum_without_nils[3]
		for i in 4..(reqs_sum_without_nils.length - 4)
			current_sum =	reqs_sum_without_nils[i] + reqs_sum_without_nils[i + 1] +
							reqs_sum_without_nils[i + 2] + reqs_sum_without_nils[i + 3]
			if current_sum > biggest_need_in_4_mins
				biggest_need_in_4_mins = current_sum
			end
		end
		return biggest_need_in_4_mins
	end
end

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

# Starts a VM and prints a the start message to stdout in the needed
# format
def start_vm(date, time, queue)
	# We sanity check the queue
	if !QUEUES.include?(queue)
		raise "Invalid queue for starting VM"
	end
	vm = Vm.new(date, time)
	vm.queue = queue
	eval "@@#{queue}_q.push vm"
	puts "#{date} #{time} launch #{queue}"
end

# Retruns the number of VMs running for the given queue
def vm_pool_size(queue)
	return eval "@@#{queue}_q.count"
end

# Retruns the VMs pool itself for a given queue
def vm_pool(queue)
	return eval "@@#{queue}_q"
end

# This stops all the running VMs
# Most like we only use this when we finished with the input data
def stop_all_vms(date, time)
	@@export_q.each do |vm|
		puts "#{date} #{time} terminate export"
	end
	@@export_q = nil
	@@url_q.each do |vm|
		puts "#{date} #{time} terminate url"
	end
	@@url_q = nil
	@@general_q.each do |vm|
		puts "#{date} #{time} terminate general"
	end
	@@general_q = nil
end

# Prints a previously read job from parts back to stdout in the needed
# format
def puts_job_back_to_stdout(date, time, uid, queue, length)
	puts "#{date} #{time} #{uid} #{queue} #{length}"
end

# We read the first line and process it first to get the start date
firstline = ARGF.readline
date, time, uid, queue, length = process_line firstline 

# This will be used to detect the last _minute_ when we adjusted the
# number of VMs because of the short trend
@@last_minute_when_trend_was_adjusted = time.split(":").drop(1).join(":")

# Now we initialize the proportional part of VMs for every queue
for i in 1..PROPORTIONAL_NUMBER_OF_VMS
	for queue in QUEUES
		start_vm date, time, queue
	end
end

# Now we initialize the Trend class
@@trend = Trend.new(date, time)
@@trend.add_req(date, time, queue, length, uid)

# Now we print the first line
puts_job_back_to_stdout date, time, uid, queue, length

# Now we process the reamining lines line by line
ARGF.each_with_index do |line, index|
	date, time, uid, queue, length = process_line line
	begin
		@@trend.add_req(date, time, queue, length, uid)
		puts_job_back_to_stdout date, time, uid, queue, length
		# When we're over the 50th second of a minute AND
		# we have not adjusted the trend in this minute yet AND
		# the trend is rising
		if	time.split(":")[2].start_with?('5') &&
			@@last_minute_when_trend_was_adjusted != time.split(":")[0..1].join(":") &&
			@@trend.short_trend(queue) > 0
				number_of_vms_to_start = (@@trend.short_trend(queue) / 5 / 60.to_f).ceil
				number_of_vms_to_start.times do
					start_vm(date, time, queue)
				end
				@@last_minute_when_trend_was_adjusted = time.split(":")[0..1].join(":")
		end
		# We check that if moderately many request has gone that what is
		# the long trend and we stop VMs when they're not needed
		if index % 1000 == 0
			QUEUES.each do |curr_queue|
				long_trend_for_q = @@trend.long_trend(curr_queue)
				pool_size = vm_pool_size(curr_queue)
#				$stderr.puts "#{date} #{time} #{curr_queue} queue size is: #{pool_size}"
				if long_trend_for_q != 0 && long_trend_for_q < pool_size * 60
					vm_pool(curr_queue).each do |vm|
						if ((vm_pool_size(curr_queue) - PROPORTIONAL_NUMBER_OF_VMS - 1) * 60) > long_trend_for_q
							vm.stop(date, time)
						end
					end
				end
			end
		end
		$stdout.flush
    rescue Errno::EPIPE
#		$stderr.puts "#{date} #{time}"
		exit 1
	end
end

# And now we terminate all the VMs, because we finished processing the
# input
stop_all_vms(date, time)

#@@trend.dump_info


