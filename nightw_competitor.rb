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

# We set up queue arrays to push VMs into them
@@export_q = Array.new
@@url_q = Array.new
@@general_q = Array.new

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

# Now we initialize the proportional part of VMs for every queue
for i in 1..PROPORTIONAL_NUMBER_OF_VMS
	for queue in QUEUES
		start_vm date, time, queue
	end
end

# Now we print the first line
puts_job_back_to_stdout date, time, uid, queue, length

# Now we process the reamining lines line by line
ARGF.each do |line|
	date, time, uid, queue, length = process_line line
	begin
		puts_job_back_to_stdout date, time, uid, queue, length
		$stdout.flush
    rescue Errno::EPIPE
		break
	end
end

# And now we terminate all the VMs, because we finished processing the
# input
stop_all_vms(date, time)
