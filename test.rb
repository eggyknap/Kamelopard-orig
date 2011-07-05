$LOAD_PATH << './lib'
require 'Kameleopard'

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
    hide_popup_for pl
    fly_to p
    show_popup_for pl

    puts get_kml
end

def numberlist
    n = NumberList.new
    n.numbers << [1, 2, 3]
end

doc
