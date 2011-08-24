gemspec = eval(File.read(Dir["*.gemspec"].first))
desc 'test kameleopard'
task :test do
    system "ruby test.rb"
end

desc 'test gemspec'
task :gemspec do
    gemspec.validate
end 

desc 'Build gem locally'
task :build => :gemspec do
    system "gem build #{gemspec.name}.gemspec"
end

desc 'Install gem locally'
task :install => :build do
    system "gem install #{gemspec.name}-#{gemspec.version}.gem"
end

desc 'Push gem to RubyGems'
task :push => :build do
    system "gem push #{gemspec.name}-#{gemspec.version}.gem"
end