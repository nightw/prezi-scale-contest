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

# We check the Ruby version and print a warning if it's not 1.9.x
if !RUBY_VERSION.start_with?('1.9')
	$stderr.puts 'WARNING: The code was tested only on Ruby 1.9!!!' 
end

# Check for stdin input availability
if $stdin.tty?
	puts 'There were no input from stdin!'
	exit 1
end

# initialize variables here to access them later on
date = time = uid = queue = length = nil

# Process the input line by line
ARGF.each do |line|
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
    puts "date: #{date}; time: #{time}; uid: #{uid}; queue: #{queue};\t length: #{length}"
end
