#!/usr/bin/env ruby
$:<<ENV['TM_SUPPORT_PATH']
$:<<ENV['TM_BUNDLE_SUPPORT']
require 'lib/dialog.rb'
require 'lib/exit_codes.rb'
require 'bin/GTD.rb'
require 'FileUtils.rb'
include GTD
include Dialog

class NormalException < Exception
end

dir = ENV['TM_GTD_DIRECTORY']
inboxfile = ENV['TM_GTD_INBOX']
unless dir && inboxfile && File.exist?(dir) && File.exist?(inboxfile) then
  TextMate.exit_show_html("<h1>Some files need to be created first!</h1>" + `#{e_sh File.join(ENV['TM_SUPPORT_PATH'],'bin',"MarkDown.pl")} #{e_sh File.join(ENV['TM_BUNDLE_SUPPORT'],"/INBOX.txt")} `)
end
tempInboxFilename = dir + "temp.gtd"
objects = GTDFile.process_directory(dir)
inbox_object = objects.find{|o| o.file == tempInboxFilename}
objects << (inbox_object = GTDFile.new(tempInboxFilename)) unless inbox_object
projects = GTDFile.projects
contexts = GTDFile.get_contexts
f = File.open(inboxfile, "r")
lines = f.readlines.map{|i| i.chomp}
f.close

$log = []
$unsorted = []
for text in lines do
  begin
    m = text.match(/^\s*@(\S+)\s+([^>]+)(?:>\s*(.*))?$/)
    raise(NormalException, text.match(/^\s*$/) ? "" : "Malformed Input Line: #{text}") unless m
    context, action, project = m[1..3]
    newContext = contexts.find_all{|c| c.downcase.index(context.downcase) != nil}
    case newContext.length
    when 0
      contexts = GTDFile.add_contexts(context)
      $log << "Created new context: #{context}."
      newContext = context
    when 1
      newContext = newContext[0]
    else
      raise NormalException, "Too many contexts matching: #{context}."
    end
    targetProj = nil
    if project == nil or project == "" then
      file = inbox_object.file
      line = 1
    else
      proj = projects.find_all{|pro| pro.name.downcase.index(project.downcase) != nil}
      case proj.length
        when 0
          raise NormalException, "Did not find any project matching: #{project}."
        when 1
          targetProj = proj[0]
          line = targetProj.end_line
          file = targetProj.file
        else
          raise NormalException, "Too many projects matching: #{project}."
      end
    end
    act = Action.new(action,newContext,targetProj,file,line,nil)
    ob = objects.find{|o| o.file.to_s == act.file.to_s}
    raise "Could not find object for file: #{act.file}" unless ob
    objs = ob.all_lines.find_all{|l| l.line >= line}
    objs.each{|l| l.line += 1}
    objs = ob.projects.find_all{|i| i.end_line >= line}
    objs.each{|i| i.end_line += 1}
    targetProj.subitems << act if targetProj
    ob.actions << act
    $log << "Added action #{act.name} with context: #{newContext} to project: #{targetProj.name if targetProj}."
  rescue NormalException => e
    $unsorted << text
    $log << e.to_s
    # raise e unless NormalException === e
    next
  rescue
    raise
  end
end
# Create files we want
data = objects.map{|o| [o.file.to_s,o.dump_object]}
# pp data
begin
  for file,string in data do
    newFile = file + "~~"
    raise if newFile == file
    File.open(newFile, 'w') do |f|
      f.puts string
    end
  end
  f = File.open(inboxfile + "~~", "w")
  f.puts $unsorted.join("\n")
  f.close
rescue Exception => e
  $log << "There was a problem saving the files: #{e}.\nExiting... Some extra files may have been created."
  puts $log.join("\n")
  exit
end
begin
  for file,string in data do
    FileUtils.mv(file,file+"~")
  end
  FileUtils.mv(inboxfile,inboxfile+"~")
  for file,string in data do
    FileUtils.mv(file+"~~",file)
  end
  FileUtils.mv(inboxfile+"~~",inboxfile)
rescue Exception => e
  $log << "There was a problem changing the files: #{e}.\nExiting... Files with extension \".gtd~~\" contain the newest data that could not be saved."
  puts $log.join("\n")
  exit
end
puts $log.join("\n")
puts "LINES THAT COULD NOT BE PROCESSED:"
puts $unsorted.join("\n")