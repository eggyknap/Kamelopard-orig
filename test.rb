$LOAD_PATH << './lib'
require 'Kameleopard'

#a = Point.new("10d11'2.23\" S", '123.283')
#b = Placemark.new 'my placemark', a
#
#t = Tour.new 'my tour'
#t << FlyTo.new(LookAt.new(b), 4)
#
#c = AbstractView.new
#begin
#    b.abstractview = 1
#rescue RuntimeError
#    puts "Abstractview stuff appears to work"
#end
#b.abstractview = c
#
#u = AnimatedUpdate.new 
#u << <<update
#    <Change>
#        <Placemark targetId="#{ b.id }">
#            <visibility>1</visibility>
#        </Placemark>
#    </Change>
#update
#
#w = Wait.new(10)
#
#t << w
#t << u
#t << w
#
#puts a.to_kml
#puts b.to_kml
#
#puts
#puts
#
#
#puts t.to_kml

p = point("123d5'23.18\" W", 239.34287)
pl = Placemark.new 'my_placemerk', p
hide_popup_for pl
fly_to p
show_popup_for pl

print_kml
