#!/usr/bin/env ruby

# The program is written for the scaling contest of Prezi.com which can
# be found here: http://prezi.com/scale/
#
# The basic concept of the algorithm is the following:
# * There are always a (comaparatively low) fixed number of virtual
#   machines available as an idle pool to process the incoming
#   requests in the near future
# * There is also a simple trend analizer for a time windows of the past
#   hour to try to guess the amount of VMs needed for the 60 minutes
# * The pool of running VMs is consisted of sum of the above constant
# number and the predicted need from the trend of last hour
#
# Or the shortest summary is that the program tries to implement
# a classic PD controller which tries to use the queues input to
# control the number of VMs used.

# Author::    Pal David Gergely  (mailto:nightw17@gmail.com)
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

# Prints a VMs start or terminate message to stdin in the needed format
def puts_queue_command(date, time, command, queue)
	# We sanity check the queue and the command
	if !QUEUES.include?(queue) || !['launch', 'terminate'].include?(command)
		return
	end
	puts "#{date} #{time} #{command} #{queue}"
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
		puts_queue_command date, time, 'launch', queue
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

# And now we terminate the proportional VMs
for i in 1..PROPORTIONAL_NUMBER_OF_VMS
	for queue in QUEUES
		puts_queue_command date, time, 'terminate', queue
	end
end
