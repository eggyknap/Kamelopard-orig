# vim:ts=4:sw=4:et:smartindent:nowrap
require 'rubygems'
require 'kameleopard'

def ids
    l = LookAt.new()
    puts l.id
end

def stylebits
    #def initialize(href, scale = 1, heading = 0, hs_x = 0.5, hs_y = 0.5, hs_xunits = :fraction, hs_yunits = :fraction, color = 'ffffffff', colormode = :normal)
    ico = IconStyle.new('')
    #def initialize(scale = 1, color = 'ffffffff', colormode = :normal)
    label = LabelStyle.new()
    #def initialize(width = 1, outercolor = 'ffffffff', outerwidth = 0, physicalwidth = 0, color = 'ffffffff', colormode = :normal)
    line = LineStyle.new()
    #def initialize(fill = 1, outline = 1, color = 'ffffffff', colormode = :normal)
    poly = PolyStyle.new()
    #def initialize(text = '', textcolor = 'ff000000', bgcolor = 'ffffffff', displaymode = :default)
    bal = BalloonStyle.new()
    #def initialize(bgcolor = nil, state = nil, href = nil, listitemtype = nil)
    list = ListStyle.new()
    return ico, label, line, poly, bal, list
end

def stylemap
    ico, label, line, poly, bal, list = stylebits
    a = Style.new(nil, nil, nil, nil, nil, list)

    s = StyleMap.new( :a => a, :b => 'test')
    puts s.to_kml
    b = Style.new(ico, nil, nil, nil, nil, nil)
    puts b.to_kml
end

def style
    ico, label, line, poly, bal, list = stylebits
    a = Style.new(ico, label, line, poly, bal, list)
#    puts a.to_kml

    b = Style.new(ico, nil, line, nil, bal, nil)
#    puts b.to_kml
    puts get_kml
end

def orig
    a = Point.new("10d11'2.23\" S", '123.283')
    b = Placemark.new 'my placemark', a

    t = Tour.new 'my tour'
    t << FlyTo.new(LookAt.new(b), 4)

    c = AbstractView.new
    begin
        b.abstractview = 1
    rescue RuntimeError
        puts "Abstractview stuff appears to work"
    end
    b.abstractview = c

    u = AnimatedUpdate.new 
    u << <<-update
        <Change>
            <Placemark targetId="#{ b.id }">
                <visibility>1</visibility>
            </Placemark>
        </Change>
    update

    w = Wait.new(10)

    t << w
    t << u
    t << w

    puts a.to_kml
    puts b.to_kml

    puts
    puts

    puts t.to_kml
end

def lang
    p = point("123d5'23.18\" W", 239.34287)
    pl = Placemark.new 'my_placemerk', p
    hide_popup_for pl
    fly_to p
    show_popup_for pl

    puts get_kml
end

def doc
    ico, label, line, poly, bal, list = stylebits
    a = Style.new(ico, label, line, poly, bal, list)
    b = Style.new(ico, nil, line, nil, bal, nil)
    p = point("123d5'23.18\" W", 239.34287)
    pl = Placemark.new 'my_placemerk', p
    name_folder 'A folder'
    name_tour 'A tour'
    hide_popup_for pl
    fly_to pl
    show_popup_for pl

    puts get_kml
end

def pointlist
    n = NDPointList.new(3)
    (1..10).each do
        a = [ rand * 100 - 50, rand * 100 - 50, rand * 100 - 50 ]
        puts "#{a[0]}  #{a[1]}  #{a[2]}"
        n << a
    end
    i = n.interpolate()
    (0..(i.size-1)).each do |a|
        puts "#{i[a][0]}  #{i[a][1]}  #{i[a][2]}"
    end
end

def pointlist_flyto
    n = NDPointList.new(2)

    p = point("117d9'25\" W", "32d42'56\" N")
    p.comment = 'San Diego'
    n << p

    p = point("2d21'9\" E", "48d51'23\" N")
    p.comment = 'Paris'
    n << p

    p = point("26d42'54\" E", "58d22'14\" N")
    p.comment = 'Tallinn'
    n << p

    p = point("18d03'51\" E", "59d19'57\" N")
    p.comment = 'Stockholm'
    n << p

    n.interpolate.each do |a|
        p = point(a[0], a[1])
        Placemark.new 'placemark', p
        f = fly_to p, 13, 9000, 'smooth'
        f.comment = "#{ a[0] } #{ a[1] }"
    end
    puts get_kml
end

def test_orbit
    p = point("112d27'21.66\" W", "38d50'24.5\" N")
    orbit p, 2000, 45, 270, -272
    puts get_kml
end

def comment_test
    p = Placemark.new 'Tallinn', point("26d42'54\" E", "58d22'14\" N")
    p.comment = 'Here is Tallinn'
    q = Placemark.new 'Stockholm', point("18d03'51\" E", "59d19'57\" N")
    q.comment = 'Here is Stockholm'
    q.point.comment = 'Here is stockholm\'s point'
    f = fly_to p, 3
    f.comment = 'This is a flyto'
    f = fly_to q, 3
    f.comment = 'This is another flyto'
end

def photooverlay
    s = Placemark.new 'Stockholm', point("18d03'51\" E", "59d19'57\" N")
    p = PhotoOverlay.new('test.png', s)
end

def groundoverlay
    ll = point("112d27'21.66\" W", "38d50'24.5\" N")
    lr = point("112d28'21.66\" W", "38d50'24.5\" N")
    ur = point("112d28'21.66\" W", "39d50'24.5\" N")
    ul = point("112d26'21.66\" W", "39d50'24.5\" N")
    p = GroundOverlay.new('test.png', nil, LatLonQuad.new(ll, lr, ur, ul), 10, :relativeToSeaFloor)
end

def region
    Placemark.new 'Fred\'s house', point("10d34'24\" E", "-18d54'34\" N")
    f = Placemark.new 'Fred\'s other house', point("10d34'20\" E", "-18d54'34\" N")
    ll = point("112d27'21.66\" W", "38d50'24.5\" N")
    lr = point("112d28'21.66\" W", "38d50'24.5\" N")
    ur = point("112d28'21.66\" W", "39d50'24.5\" N")
    ul = point("112d26'21.66\" W", "39d50'24.5\" N")
#    f.geometry << LineString.new( [ll, lr, ur, ul, ll] )
    f.geometry << LinearRing.new( [ll, lr, ur, ul, ll] )
#    latlon = LatLonBox.new( "-18d54'00\" N", "-18d56'00\" N", "10d34'00\" E", "10d30'00\" E", 10 )
#    lod = Lod.new(128, 1024, 128, 128)
#    f.region = Region.new(latlon, lod)
end

region
puts get_kml
