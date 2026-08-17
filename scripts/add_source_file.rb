#!/usr/bin/env ruby
# frozen_string_literal: true

# Adds a source file to a target in pass.xcodeproj.
#
# The project uses explicit file references rather than Xcode 16 synchronized
# groups, so a new .swift file is invisible to the build until it is registered
# here. Editing project.pbxproj by hand means inventing unique object IDs; this
# uses the xcodeproj gem instead.
#
#   ruby scripts/add_source_file.rb passKit passKit/Models/Foo.swift

require 'xcodeproj'

PROJECT = File.expand_path('../pass.xcodeproj', __dir__)

target_name = ARGV.shift
file_paths = ARGV

abort "usage: add_source_file.rb <target> <path...>" if target_name.nil? || file_paths.empty?

project = Xcodeproj::Project.open(PROJECT)
target = project.targets.find { |t| t.name == target_name }
abort "no such target: #{target_name}" if target.nil?

file_paths.each do |path|
  group = project.main_group
  File.dirname(path).split('/').each do |component|
    child = group.children.find do |c|
      c.display_name == component && c.is_a?(Xcodeproj::Project::Object::PBXGroup)
    end
    group = child || group.new_group(component, component)
  end

  basename = File.basename(path)
  if group.files.any? { |f| f.display_name == basename }
    puts "already referenced: #{path}"
    next
  end

  reference = group.new_reference(basename)
  target.add_file_references([reference])
  puts "added: #{path} -> #{target_name}"
end

project.save
