require 'Kameleopard'

a = Point.new("10d11'2.23\" S", '123.283')
puts a.to_s

b = Placemark.new 'my placemark'
b.geometry = a

t = Tour.new 'my tour'
t << FlyTo.new(LookAt.new(b), 4)

c = AbstractView.new
begin
    b.abstractview = 1
rescue RuntimeError
    puts "Abstractview stuff appears to work"
end
b.abstractview = c

puts a.to_kml
puts b.to_kml

puts
puts


puts t.to_kml
