def self.tick(args)
  File.open('C:/source/dragonruby/drecs/smoke_log.txt', 'a') { |f| f.puts "[smoke] tick #{args.state.tick_count}" }
  $gtk.exit if args.state.tick_count >= 3
end
