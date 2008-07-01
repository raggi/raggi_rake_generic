# 
# = raggi's Rake Generic Tasks
# 
# A generic rake task set, supporting several forms of testing environment, 
# gem installs, and so on. Rides on top of a gem specification, and rake 
# built-ins.
# 
# You will need to define a GSpec method or object (constant scope) to pass 
# back a gem specification for the project. Crufty rake tasks will be removed 
# as you remove portions of the specification from your gemspec.
# 
# Suggestions, fixes and additions always welcome.
# 

require 'rubygems'
require 'rake/gempackagetask'
require 'rake/testtask'
require 'rake/rdoctask'
require 'rake/clean'

module FileUtils
  # If any of these methods ever clobber, try removing them.
  # Hopefully they'll do something semantically similar.
  abort "Err: #{__FILE__}:#{__LINE__} monkey patch windows? clobbers!" unless instance_methods.grep(/windows\?/).empty?
  abort "Err: #{__FILE__}:#{__LINE__} monkey patch sudo clobbers!" unless instance_methods.grep(/sudo/).empty?
  abort "Err: #{__FILE__}:#{__LINE__} monkey patch gem_cmd clobbers!" unless instance_methods.grep(/gem_cmd/).empty?
  def windows?; RUBY_PLATFORM =~ /mswin|mingw/; end
  def sudo(cmd)
    if windows? || (require 'etc'; Etc.getpwuid.uid == 0)
      sh cmd
    else
      sh "sudo #{cmd}"
    end
  end
  def gem_cmd(action, name, *args)
    rb = Gem.ruby rescue nil
    rb ||= (require 'rbconfig'; File.join(Config::CONFIG['bindir'], Config::CONFIG['ruby_install_name']))
    sudo "#{rb} -r rubygems -e 'require %{rubygems/gem_runner}; Gem::GemRunner.new.run(%w{#{action} #{name} #{args.join(' ')}})'"
  end
end

# Setup our packaging tasks, we're just jacking the builtins.
Rake::GemPackageTask.new(GSpec) do |pkg|
  pkg.need_tar, pkg.need_tar_gz, pkg.need_zip = true, true, true if Package
  pkg.gem_spec = GSpec
end
Rake::Task[:clobber].enhance [:clobber_package]

# Test tasks can be made up of spec files or test files, provided you require
# the right stuff in your test / spec helpers.
Rake::TestTask.new do |t|
  t.libs = Array(GSpec.require_path || 'lib')
  t.warning = true
  t.pattern = '{spec,test}/**/*.rb'
end

# Use {test,spec}/runner for alternative spec framework runners & rubygems 
# test runner file.
if runner = Dir['{spec,test}/runner'].first
  desc "Run tests using #{runner}"
  task :spec do ruby runner end
else
  task :spec => :test # pass on to a generic test task!
end

# Only generate rdoc if the spec says so, again, jack the builtins.
if GSpec.has_rdoc
  Rake::RDocTask.new do |rd|
    rd.title = GSpec.name
    rd.rdoc_dir = 'rdoc'
    rd.main = "README" if test ?e, "README"
    rd.main ||= "docs/README" if test ?e, "docs/README"
    rd.rdoc_files.include("lib/**/*.rb", *GSpec.extra_rdoc_files)
  end
  Rake::Task[:clobber].enhance [:clobber_rdoc]

  desc 'Generate and open documentation'
  task :docs => :rdoc do
    case RUBY_PLATFORM
    when /darwin/       ; sh 'open rdoc/index.html'
    when /mswin|mingw/  ; sh 'start rdoc\index.html'
    else 
      sh 'firefox rdoc/index.html'
    end
  end
end

if GSpec.default_executable
  desc "Run #{GSpec.default_executable}"
  task :run do ruby File.join(GSpec.bindir, GSpec.default_executable) end
end

desc 'Install gem (and sudo if required)'
task :install => :package do 
  gem_cmd(:install, "pkg/#{GSpec.name}-#{GSpec.version}.gem")
end

desc 'Uninstall gem (and sudo if required)'
task :uninstall do
  gem_cmd(:uninstall, "#{GSpec.name}")
end

# Find an scm's store directory, if we do, make a task to commit to it only
# after running all the tests (successfully).
if scm = %w(git svn bzr hg).find { |d| File.directory? ".#{d}" }
  desc "Run tests then commit to #{scm}"
  task :commit => :test do sh "#{scm} commit" end
end