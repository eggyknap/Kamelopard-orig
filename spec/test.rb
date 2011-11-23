# vim:ts=4:sw=4:et:smartindent:nowrap
$LOAD_PATH << './lib'
require 'kamelopard'
require 'rexml/document'

# XXX test everything's to_kml(elem), instead of just to_kml(nil)

def test_lat_lon_quad(d, n)
    d.elements['//coordinates'].text.should == "#{n},#{n} #{n},#{n} #{n},#{n} #{n},#{n}"
end

def test_lat_lon_box(l, latlon)
    l.elements['//north'].text.should == latlon.north.to_s
    l.elements['//south'].text.should == latlon.south.to_s
    l.elements['//east'].text.should == latlon.east.to_s
    l.elements['//west'].text.should == latlon.west.to_s
end

def test_lod(d, lodval)
    %w[ minLodPixels maxLodPixels minFadeExtent maxFadeExtent ].each do |f|
        d.elements["//#{f}"].text.to_i.should == lodval
    end
end

def check_kml_values(o, values)
    values.each do |k, v|
        o.method("#{k}=").call(v)
        o.to_kml.elements["//#{k}"].text.should == v.to_s
    end
end

def fields_exist(o, fields)
    fields.each do |f|
        o.should respond_to(f.to_sym)
        o.should respond_to("#{f}=".to_sym)
    end
end

def match_view_vol(x, e)
    %w[ near rightFov topFov ].each do |a|
        x.elements["//#{a}"].text.to_i.should == e
    end
    %w[ leftFov bottomFov ].each do |a|
        x.elements["//#{a}"].text.to_i.should == -e
    end
end

def match_image_pyramid(x, e)
    %w[ tileSize maxWidth maxHeight gridOrigin ].each do |a|
        x.elements["//#{a}"].text.to_i.should == e
    end
end

def validate_abstractview(k, type, point, heading, tilt, roll, range, mode)
    [
        [ k.root.name != type, "Wrong type #{ k.root.name }" ],
        [ k.elements['//longitude'].text.to_f != point.longitude, 'Wrong longitude' ],
        [ k.elements['//longitude'].text.to_f != point.longitude, 'Wrong longitude' ],
        [ k.elements['//latitude'].text.to_f != point.latitude, 'Wrong latitude' ],
        [ k.elements['//altitude'].text.to_f != point.altitude, 'Wrong altitude' ],
        [ k.elements['//heading'].text.to_f != heading, 'Wrong heading' ],
        [ k.elements['//tilt'].text.to_f != tilt, 'Wrong tilt' ],
        [ type == 'Kamelopard::LookAt' && k.elements['//range'].text.to_f != range, 'Wrong range' ],
        [ type == 'Kamelopard::Camera' && k.elements['//roll'].text.to_f != roll, 'Wrong roll' ],
        [ mode !~ /SeaFloor/ && k.elements['//altitudeMode'] != mode.to_s, 'Wrong altitude mode' ],
        [ mode =~ /SeaFloor/ && k.elements['//gx:altitudeMode'] != mode.to_s, 'Wrong gx:altitudeMode' ]
    ].each do |a|
        return [false, a[1]] if a[0]
    end
end

def get_test_substyles()
    i = Kamelopard::IconStyle.new 'icon'
    la = Kamelopard::LabelStyle.new
    lin = Kamelopard::LineStyle.new
    p = Kamelopard::PolyStyle.new
    b = Kamelopard::BalloonStyle.new 'balloon'
    lis = Kamelopard::ListStyle.new
    [ i, la, lin, p, b, lis ]
end

def get_test_styles()
    i, la, lin, p, b, lis = get_test_substyles()
    
    si = Kamelopard::Style.new i
    sl = Kamelopard::Style.new i, la, lin, p, b, lis
    sm = Kamelopard::StyleMap.new( { :icon => si, :list => sl } )
    
    si.id = 'icon'
    sl.id = 'list'
    sm.id = 'map'

    [ si, sl, sm ]
end

def check_time_primitive(set_var_lambda, get_kml_lambda, xpath)
    b = '2011-01-01'
    e = '2011-02-01'
    w = '2011-01-01'
    tn = Kamelopard::TimeSpan.new(b, e)
    tm = Kamelopard::TimeStamp.new(w)

    set_var_lambda.call(tn)
    d = get_kml_lambda.call
    t = d.elements[xpath + '//TimeSpan' ]
    t.elements['begin'].text.should == b
    t.elements['end'].text.should == e

    set_var_lambda.call(tm)
    d = get_kml_lambda.call
    t = d.elements[xpath + '//TimeStamp' ]
    t.elements['when'].text.should == w
end

def get_kml_header
    <<-header
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2" xmlns:kml="http://www.opengis.net/kml/2.2" xmlns:atom="http://www.w3.org/2005/Atom">
<Document>
    header
end

shared_examples_for 'field_producer' do
    it 'has the right attributes' do
        fields_exist @o, @fields
    end
end

shared_examples_for 'Kamelopard::Object' do
    it 'descends from Kamelopard::Object' do
        @o.kind_of?(Kamelopard::Object).should == true
    end

    it 'has an id' do
        @o.id.should_not be_nil
    end

    it 'allows a comment' do
        @o.should respond_to(:comment)
        @o.should respond_to(:comment=)
    end

    it 'should put its comment in the KML' do
        @o.comment = 'Look for this string'
        k = @o.to_kml
        k.to_s.should =~ /Look for this string/
    end
end

shared_examples_for 'altitudeMode' do
    it 'uses the right altitudeMode element' do
        [:absolute, :clampToGround, :relativeToGround].each do |m|
            @o.altitudeMode = m
            @o.to_kml.elements["//altitudeMode"].text.should == m.to_s
        end

        [:clampToSeaFloor, :relativeToSeaFloor].each do |m|
            @o.altitudeMode = m
            @o.to_kml.elements["//gx:altitudeMode"].text.should == m.to_s
        end
    end
end

shared_examples_for 'KML_includes_id' do
    it 'should include the object ID in the KML' do
        d = @o.to_kml
        d.root.attributes['id'].should_not be_nil
    end
end

shared_examples_for 'KML_producer' do
    it 'should have a to_kml function' do
        @o.should respond_to(:to_kml)
    end

    it 'should create a REXML document when to_xml is called' do
        @o.to_kml.class.should_not == String
    end
end

shared_examples_for 'Kamelopard::Geometry' do
    it_should_behave_like 'Kamelopard::Object'

    it 'descends from Kamelopard::Geometry' do
        @o.kind_of?(Kamelopard::Geometry).should == true
    end
end

shared_examples_for 'Kamelopard::AbstractView' do
    it_should_behave_like 'Kamelopard::Object'
    it_should_behave_like 'altitudeMode'
    it_should_behave_like 'KML_includes_id'
    it_should_behave_like 'KML_producer'

    it 'descends from Kamelopard::AbstractView' do
        @o.kind_of?(Kamelopard::AbstractView).should == true
    end

    it 'accepts viewer options and includes them in the KML' do
        k = @o.to_kml
        k.should_not =~ /ViewerOptions/

        @o[:streetview] = true
        @o[:sunlight] = true
        @o[:historicalimagery] = true
        k = @o.to_kml
        k.elements["//ViewerOptions | //gx:ViewerOptions"].should_not be_nil
        k.elements["//gx:option[@name='sunlight',@enabled='true']"].should_not be_nil
        k.elements["//gx:option[@name='streetview',@enabled='true']"].should_not be_nil
        k.elements["//gx:option[@name='historicalimagery',@enabled='true']"].should_not be_nil

        @o[:streetview] = false
        @o[:sunlight] = false
        @o[:historicalimagery] = false
        k = @o.to_kml
        k.elements["//ViewerOptions | //gx:ViewerOptions"].should_not be_nil
        k.elements["//gx:option[@name='sunlight',@enabled='false']"].should_not be_nil
        k.elements["//gx:option[@name='streetview',@enabled='false']"].should_not be_nil
        k.elements["//gx:option[@name='historicalimagery',@enabled='false']"].should_not be_nil
    end

    it 'whines when a strange option is provided' do
        lambda { @o[:something_strange] = true }.should raise_exception
        lambda { @o[:streetview] = true }.should_not raise_exception
        lambda { @o[:sunlight] = true }.should_not raise_exception
        lambda { @o[:historicalimagery] = true }.should_not raise_exception
    end
end
 
shared_examples_for 'Kamelopard::CoordinateList' do
    it 'returns coordinates in its KML' do
        @o << [[1,2,3], [2,3,4], [3,4,5]]
        k = @o.to_kml
        e = k.elements['//coordinates']
        e = k.root if e.nil?

        e.should_not be_nil
        e.name.should == 'coordinates'
        e.text.should =~ /1.0,2.0,3.0/
        e.text.should =~ /2.0,3.0,4.0/
        e.text.should =~ /3.0,4.0,5.0/
    end

    describe 'when adding elements' do
        it 'accepts arrays of arrays' do
            @o << [[1,2,3], [2,3,4], [3,4,5]]
        end

        it 'accepts Kamelopard::Points' do
            @o << Kamelopard::Point.new(3,2,1)
        end

        it 'accepts arrays of points' do
            q = []
            [[1,2,3], [2,3,4], [3,4,5]].each do |a|
                q << Kamelopard::Point.new(a[0], a[1], a[2])
            end
            @o << q
        end

        it 'accepts another Kamelopard::CoordinateList' do
            p = Kamelopard::CoordinateList.new( [[1,2,3], [2,3,4], [3,4,5]] )
            @o << p
        end

        it 'complains when trying to add something weird' do
            a = REXML::Document.new('<a>b</a>')
            lambda { @o << a }.should raise_error
        end
    end

end

shared_examples_for 'Kamelopard::Camera-like' do
    it_should_behave_like 'Kamelopard::AbstractView'

    it 'has the right attributes' do
        fields = %w[ timestamp timespan options longitude latitude altitude heading tilt roll altitudeMode ]
        fields_exist @o, fields
    end

    it 'contains the right KML attributes' do
        @o.heading = 12
        @o.tilt = 12
        k = @o.to_kml
        k.elements['//longitude'].should_not be_nil
        k.elements['//latitude'].should_not be_nil
        k.elements['//altitude'].should_not be_nil
        k.elements['//heading'].should_not be_nil
        k.elements['//tilt'].should_not be_nil
    end
end

shared_examples_for "Kamelopard::TimePrimitive" do
    it_should_behave_like 'Kamelopard::Object'
    it_should_behave_like 'KML_producer'
    it_should_behave_like 'KML_includes_id'

    it 'descends from Kamelopard::TimePrimitive' do
        @o.kind_of?(Kamelopard::TimePrimitive).should == true
    end
end

shared_examples_for 'Kamelopard::Feature' do
    def document_has_styles(d)
        si = d.elements['//Style[@id="icon"]']
        raise 'Could not find iconstyle' if si.nil?
        sl = d.elements['//Style[@id="list"]']
        raise 'Could not find liststyle' if sl.nil?
        sm = d.elements['//StyleMap[@id="map"]']
        raise 'Could not find stylemap' if sm.nil?

        si = d.elements['//StyleMap/Pair/Style[@id="icon"]']
        raise 'Could not find iconstyle in stylemap' if si.nil?
        sl = d.elements['//StyleMap/Pair/Style[@id="list"]']
        raise 'Could not find liststyle in stylemap' if sl.nil?
        true
    end

    it_should_behave_like 'Kamelopard::Object'
    it_should_behave_like 'KML_includes_id'
    it_should_behave_like 'KML_producer'

    it 'descends from Kamelopard::Feature' do
        @o.kind_of?(Kamelopard::Feature).should == true
    end

    it 'has the right attributes' do
        fields = %w[
            visibility open atom_author atom_link name
            phoneNumber snippet description abstractView timestamp
            timespan styleUrl styleSelector region metadata
            extendedData styles
        ]
        fields_exist @o, fields

        @o.should respond_to(:addressDetails)
    end

    it 'handles extended address stuff correctly' do
        @o.addressDetails = 'These are some extended details'
        k = Kamelopard::Document.instance.get_kml_document
        k.root.attributes['xmlns:xal'].should == 'urn:oasis:names:tc:ciq:xsdschema:xAL:2.0'
        k = @o.to_kml
        k.elements['//xal:AddressDetails'].text.should == @o.addressDetails
    end

    it 'handles styles correctly' do
        get_test_styles().each do |s|
            @o.styleUrl = s
            @o.to_kml.elements['//styleUrl'].text.should == "##{s.id}"
        end
        @o.styleUrl = '#random'
        @o.to_kml.elements['//styleUrl'].text.should == '#random'
    end

    it 'returns style KML correctly' do
        get_test_styles().each do |s|
            @o.styles << s
        end

        header = get_kml_header
        e = REXML::Element.new 'test'
        @o.styles_to_kml e
        
        document_has_styles(e).should == true
    end

    it 'returns the right KML for simple fields' do
        marker = 'Look for this string'
        fields = %w( name address phoneNumber description styleUrl )
        fields.each do |f|
            p = Kamelopard::Feature.new()
            Kamelopard::Document.instance.folder << p
            p.instance_variable_set("@#{f}".to_sym, marker)
            e = p.to_kml.elements["//#{f}"]
            e.should_not be_nil
            e.text.should == marker
        end
    end

    it 'returns the right KML for more complex fields' do
        marker = 'Look for this string'
        [
            [ :@addressDetails, 'xal:AddressDetails' ],
            [ :@metadata, 'Metadata' ],
            [ :@extendedData, 'ExtendedData' ],
            [ :@atom_link, 'atom:link' ]
        ].each do |a|
            p = Kamelopard::Feature.new()
            p.instance_variable_set(a[0], marker)
            e = p.to_kml.elements["//#{a[1]}"]
            e.should_not be_nil
            e.text.should == marker
        end
    end

    it 'correctly KML-ifies the atom:author field' do
        o = Kamelopard::Feature.new()
        marker = 'Look for this text'
        o.atom_author = marker
        o.to_kml.elements['//atom:author/atom:name'].text.should == marker
    end

    it 'returns the right KML for boolean fields' do
        %w( visibility open ).each do |k|
            [false, true].each do |v|
                o = Kamelopard::Feature.new()
                o.instance_variable_set("@#{k}".to_sym, v)
                o.to_kml.elements["//#{k}"].text.to_i.should == (v ? 1 : 0)
            end
        end
    end

    it 'correctly KML\'s the Kamelopard::Snippet' do
        maxlines = 2
        text = "This is my snippet\nIt's more than two lines long.\nNo, really."
        @o.snippet = Kamelopard::Snippet.new(text, maxlines)
        s = @o.to_kml.elements["//Snippet[@maxLines='#{ maxlines }']"]
        s.should_not be_nil
        s.text.should == text
    end

    describe 'correctly produces Kamelopard::Region KML' do
        before(:all) do
            @o = Kamelopard::Feature.new('my feature')
            @latlon = Kamelopard::LatLonBox.new( 1, -1, 1, -1, 10 )
            @lod = Kamelopard::Lod.new(128, 1024, 128, 128)
            @r = Kamelopard::Region.new(@latlon, @lod)
            @o.region = @r

            @reg = @o.to_kml.elements['//Region']
            @l = @reg.elements['LatLonAltBox']
            @ld = @reg.elements['Lod']
        end

        it 'creates a Kamelopard::Region element' do
            @reg.should_not be_nil
            @reg.attributes['id'].should == @r.id
        end

        it 'creates the right LatLonAltBox' do 
            @l.should_not be_nil
            test_lat_lon_box(@l, @latlon)
        end

        it 'creates the right LOD' do
            @ld.should_not be_nil
            @ld.elements['minLodPixels'].text.should == @lod.minpixels.to_s
            @ld.elements['maxLodPixels'].text.should == @lod.maxpixels.to_s
            @ld.elements['minFadeExtent'].text.should == @lod.minfade.to_s
            @ld.elements['maxFadeExtent'].text.should == @lod.maxfade.to_s
        end

    end

    it 'correctly KML\'s the Kamelopard::StyleSelector' do
        @o = Kamelopard::Feature.new 'StyleSelector test'
        get_test_styles.each do |s| @o.styles << s end
        document_has_styles(@o.to_kml).should == true
    end

    it 'correctly KML\'s the Kamelopard::TimePrimitive' do
        check_time_primitive(
            lambda { |t| @o.timeprimitive = t },
            lambda { @o.to_kml },
            ''
        )
    end

    it 'correctly KML\'s the Kamelopard::AbstractView' do
        long, lat, alt = 13, 12, 11
        heading, tilt, roll, range, mode = 1, 2, 3, 4, :clampToSeaFloor
        p = Kamelopard::Point.new(long, lat, alt)
        camera = Kamelopard::Camera.new p, heading, tilt, roll
        lookat = Kamelopard::LookAt.new p, heading, tilt, range
        @o.abstractView = camera
        a = @o.to_kml.elements['//Camera']
        a.should_not be_nil
        validate_abstractview(a, 'Camera', p, heading, tilt, roll, range, mode).should be_true 
        @o.abstractView = lookat
        a = @o.to_kml.elements['//LookAt']
        a.should_not be_nil
        validate_abstractview(a, 'LookAt', p, heading, tilt, roll, range, mode).should be_true 
    end
end

shared_examples_for 'Kamelopard::Container' do
    it 'should handle <<' do
        @o.should respond_to('<<')
    end
end

shared_examples_for 'Kamelopard::ColorStyle' do
    it_should_behave_like 'Kamelopard::Object'
    it_should_behave_like 'KML_includes_id'
    it_should_behave_like 'KML_producer'

    it 'should accept only valid color modes' do
        @o.colorMode = :normal
        @o.colorMode = :random
        begin
            @o.colorMode = :something_wrong
        rescue RuntimeError => f
            q = f.to_s
        end
        q.should =~ /colorMode must be either/
    end

    it 'should allow setting and retrieving alpha, blue, green, and red' do
        a = 'ab'
        @o.alpha = a
        @o.alpha.should == a
        @o.blue = a
        @o.blue.should == a
        @o.green = a
        @o.green.should == a
        @o.red = a
        @o.red.should == a
    end

    it 'should get settings in the right order' do
        @o.alpha = 'de'
        @o.blue = 'ad'
        @o.green = 'be'
        @o.red = 'ef'
        @o.color.should == 'deadbeef'
    end

    it 'should do its KML right' do
        color = 'abcdefab'
        colorMode = :random
        @o.color = color
        @o.colorMode = colorMode
        d = @o.to_kml
        d.elements['//color'].text.should == color
        d.elements['//colorMode'].text.should == colorMode.to_s
    end
end

shared_examples_for 'StyleSelector' do
    it_should_behave_like 'Kamelopard::Object'
    it_should_behave_like 'KML_producer'
    it_should_behave_like 'KML_includes_id'

    it 'should handle being attached to stuff' do
        @o.should respond_to(:attach)
        p = Kamelopard::Placemark.new Kamelopard::Point.new(123, 23), 'test'
        @o.attach(p)
        @o.attached?.should be_true
    end
end

shared_examples_for 'KML_root_name' do
    it 'should have the right namespace and root' do
        d = @o.to_kml
        if ! @ns.nil? then
            ns_url = 'http://www.google.com/kml/ext/2.2'
            d.add_namespace @ns, ns_url
            d.root.namespace.should == ns_url
        end
        d.root.name.should == @o.class.name.gsub('Kamelopard::', '')
    end
end

shared_examples_for 'Kamelopard::TourPrimitive' do
    before(:each) do
        @ns = 'gx'
    end

    it_should_behave_like 'Kamelopard::Object'
    it_should_behave_like 'KML_includes_id'
    it_should_behave_like 'KML_producer'
    it_should_behave_like 'KML_root_name'
end

shared_examples_for 'Kamelopard::Overlay' do
    it_should_behave_like 'Kamelopard::Feature'

    it 'should have the right KML' do
        href = 'look for this href'
        drawOrder = 10
        color = 'ffffff'
        @o.icon = Kamelopard::Icon.new href
        @o.drawOrder = drawOrder
        @o.color = color

        d = @o.to_kml
        d.elements['//href'].text.should == href
        d.elements['//color'].text.should == color
        d.elements['//drawOrder'].text.to_i.should == drawOrder
    end
end

describe 'Kamelopard::Point' do
    before(:each) do
        @attrs = { :lat => 12.4, :long => 34.2, :alt => 500 }
        @fields = %w[ latitude longitude altitude altitudeMode extrude ]
        @o = Kamelopard::Point.new @attrs[:long], @attrs[:lat], @attrs[:alt]
    end

    it_should_behave_like 'KML_includes_id'
    it_should_behave_like 'Kamelopard::Geometry'
    it_should_behave_like 'field_producer'

    it 'accepts different coordinate formats' do
        coords = [ [ '123D30m12.2s S', '34D56m24.4s E' ],
                   [ '32d10\'23.10" N', -145.3487 ],
                   [ 123.5985745,      -45.32487 ] ]
        coords.each do |a|
            lambda { Kamelopard::Point.new a[1], a[0] }.should_not raise_error
        end
    end

    it 'does not accept coordinates that are out of range' do
        q = ''
        begin
            Kamelopard::Point.new 342.32487, 45908.123487
        rescue RuntimeError => f
            q = f.to_s
        end
        q.should =~ /out of range/
    end

    describe 'KML output' do
        it_should_behave_like 'KML_producer'
        it_should_behave_like 'altitudeMode'

        it 'has the right coordinates' do
            k = @o.to_kml
            k.elements['//coordinates'].text.should == "#{ @attrs[:long] }, #{ @attrs[:lat] }, #{ @attrs[:alt] }"
        end

        it 'handles extrude properly' do
            @o.extrude = true 
            k = @o.to_kml
            k.elements['//extrude'].text.should == '1'
            @o.extrude = false 
            k = @o.to_kml
            k.elements['//extrude'].text.should == '0'
        end

        it 'provides the correct short form' do
            @o.altitudeMode = :clampToSeaFloor
            @o.extrude = 1
            k = @o.to_kml(true)
            k.elements['//extrude'].should be_nil
            k.elements['//altitudeMode'].should be_nil
        end
    end
end

describe 'Kamelopard::CoordinateList' do
    before(:each) do
        @o = Kamelopard::CoordinateList.new
    end

    it_should_behave_like 'KML_producer'

    it 'has the right attributes and methods' do
        @o.should respond_to(:coordinates)
        @o.should respond_to(:<<)
        @o.should respond_to(:add_element)
    end

    it_should_behave_like 'Kamelopard::CoordinateList'
end

describe 'Kamelopard::LineString' do
    before(:each) do
        @o = Kamelopard::LineString.new([ [1,2,3], [2,3,4], [3,4,5] ])
        @fields = %w[
            altitudeOffset extrude tessellate altitudeMode
            drawOrder longitude latitude altitude
        ]
    end

    it_should_behave_like 'altitudeMode'
    it_should_behave_like 'KML_includes_id'
    it_should_behave_like 'KML_producer'
    it_should_behave_like 'Kamelopard::Geometry'
    it_should_behave_like 'Kamelopard::CoordinateList'
    it_should_behave_like 'field_producer'

    it 'contains the right KML attributes' do
        @o.altitudeOffset = nil
        @o.to_kml.elements['//gx:altitudeOffset'].should be_nil
        @o.altitudeOffset = 1
        @o.to_kml.elements['//gx:altitudeOffset'].should_not be_nil
        @o.extrude = nil
        @o.to_kml.elements['//extrude'].should be_nil
        @o.extrude = true 
        @o.to_kml.elements['//extrude'].should_not be_nil
        @o.tessellate = nil
        @o.to_kml.elements['//tessellate'].should be_nil
        @o.tessellate = true 
        @o.to_kml.elements['//tessellate'].should_not be_nil
        @o.drawOrder = nil
        @o.to_kml.elements['//gx:drawOrder'].should be_nil
        @o.drawOrder = true 
        @o.to_kml.elements['//gx:drawOrder'].should_not be_nil
    end
end

describe 'Kamelopard::LinearRing' do
    before(:each) do
        @o = Kamelopard::LinearRing.new([ [1,2,3], [2,3,4], [3,4,5] ])
        @fields = %w[ altitudeOffset extrude tessellate altitudeMode ]
    end

    it_should_behave_like 'altitudeMode'
    it_should_behave_like 'KML_includes_id'
    it_should_behave_like 'KML_producer'
    it_should_behave_like 'Kamelopard::Geometry'
    it_should_behave_like 'Kamelopard::CoordinateList'
    it_should_behave_like 'field_producer'

    it 'contains the right KML attributes' do
        @o.altitudeOffset = nil
        @o.to_kml.elements['gx:altitudeOffset'].should be_nil
        @o.altitudeOffset = 1
        @o.to_kml.elements['gx:altitudeOffset'].should_not be_nil
        @o.extrude = nil
        @o.to_kml.elements['extrude'].should be_nil
        @o.extrude = true 
        @o.to_kml.elements['extrude'].should_not be_nil
        @o.tessellate = nil
        @o.to_kml.elements['tessellate'].should be_nil
        @o.tessellate = true 
        @o.to_kml.elements['tessellate'].should_not be_nil
    end
end

describe 'Kamelopard::Camera' do
    before(:each) do
        @o = Kamelopard::Camera.new Kamelopard::Point.new(123, -123, 123), 10, 10, 10, :clampToGround
        @fields = [ 'roll' ]
    end

    it_should_behave_like 'Kamelopard::Camera-like'
    it_should_behave_like 'field_producer'

    it 'contains the right KML attributes' do
        @o.roll = 12
        k = @o.to_kml
        k.elements['//roll]'].text.should == '12'
    end
end

describe 'Kamelopard::LookAt' do
    before(:each) do
        @o = Kamelopard::LookAt.new Kamelopard::Point.new(123, -123, 123), 10, 10, 10, :clampToGround
        @fields = [ 'range' ]
    end

    it_should_behave_like 'Kamelopard::Camera-like'
    it_should_behave_like 'field_producer'
    it_should_behave_like 'KML_root_name'

    it 'contains the right KML attributes' do
        @o.range = 10
        k = @o.to_kml
        k.elements['[range=10]'].should_not be_nil
    end
end

describe 'Kamelopard::TimeStamp' do
    before(:each) do
        @when = '01 Dec 1934 12:12:12 PM'
        @o = Kamelopard::TimeStamp.new @when
        @fields = [ :when ]
    end

    it_should_behave_like 'Kamelopard::TimePrimitive'
    it_should_behave_like 'field_producer'
    it_should_behave_like 'KML_root_name'

    it 'has the right KML elements' do
        k = @o.to_kml
        k.elements["[when='#{ @when }']"].should_not be_nil
    end
end

describe 'Kamelopard::TimeSpan' do
    before(:each) do
        @begin = '01 Dec 1934 12:12:12 PM'
        @end = '02 Dec 1934 12:12:12 PM'
        @o = Kamelopard::TimeSpan.new @begin, @end
        @fields = %w[ begin end ]
    end

    it_should_behave_like 'Kamelopard::TimePrimitive'
    it_should_behave_like 'field_producer'
    it_should_behave_like 'KML_root_name'

    it 'has the right KML elements' do
        k = @o.to_kml
        k.elements["[begin='#{ @begin }']"].should_not be_nil
        k.elements["[end='#{ @end }']"].should_not be_nil
    end
end

describe 'Kamelopard::Feature' do
    before(:each) do
        @o = Kamelopard::Feature.new('Some feature')
        @fields = []
    end

    it_should_behave_like 'Kamelopard::Feature'
end

describe 'Kamelopard::Container' do
    before(:each) do
        @o = Kamelopard::Container.new
    end

    it_should_behave_like 'Kamelopard::Container'
end

describe 'Kamelopard::Folder' do
    before(:each) do
        @o = Kamelopard::Folder.new('test folder')
        @fields = []
    end
    it_should_behave_like 'Kamelopard::Container'
    it_should_behave_like 'Kamelopard::Feature'
end

describe 'Kamelopard::Document' do
    before(:each) do
        @o = Kamelopard::Document.instance
        @fields = []
    end

    it_should_behave_like 'Kamelopard::Container'
    it_should_behave_like 'Kamelopard::Feature'

    it 'should return a tour' do
        @o.should respond_to(:tour)
        @o.tour.class.should == Kamelopard::Tour
    end

    it 'should return a folder' do
        @o.should respond_to(:folder)
        @o.folder.class.should == Kamelopard::Folder
    end

    it 'should have a get_kml_document method' do
        @o.should respond_to(:get_kml_document)
        @o.get_kml_document.class.should == REXML::Document
    end
end

describe 'Kamelopard::ColorStyle' do
    before(:each) do
        @o = Kamelopard::ColorStyle.new 'ffffffff'
    end

    it_should_behave_like 'Kamelopard::ColorStyle'
    it_should_behave_like 'KML_root_name'

    it 'should return the right KML' do
        @o.color = 'deadbeef'
        @o.colorMode = :random
        d = @o.to_kml
        d.elements['//color'].text.should == 'deadbeef'
        d.elements['//colorMode'].text.should == 'random'
    end
end

describe 'Kamelopard::BalloonStyle' do
    before(:each) do
        @o = Kamelopard::BalloonStyle.new 'balloon text'
        @o.textColor = 'deadbeef'
        @o.bgColor = 'deadbeef'
        @o.displayMode = :hide
    end

    it_should_behave_like 'Kamelopard::Object'
    it_should_behave_like 'KML_includes_id'
    it_should_behave_like 'KML_producer'
    it_should_behave_like 'KML_root_name'

    it 'should have the right attributes' do
        @o.bgColor.should == 'deadbeef'
        @o.textColor.should == 'deadbeef'
        @o.displayMode.should == :hide
    end

    it 'should return the right KML' do
        s = @o.to_kml
        s.elements['//text'].text.should == 'balloon text'
        s.elements['//bgColor'].text.should == 'deadbeef'
        s.elements['//textColor'].text.should == 'deadbeef'
        s.elements['//displayMode'].text.should == 'hide'
    end
end

describe 'Kamelopard::XY' do
    before(:each) do
        @x, @y, @xunits, @yunits = 0.2, 13, :fraction, :pixels
        @o = Kamelopard::XY.new @x, @y, @xunits, @yunits
    end

    it 'should return the right KML' do
        d = @o.to_kml 'test'
        d.root.name = 'test'
        d.attributes['x'].to_f.should == @x
        d.attributes['y'].to_f.should == @y
        d.attributes['xunits'].to_sym.should == @xunits
        d.attributes['yunits'].to_sym.should == @yunits
    end
end

describe 'Kamelopard::Icon' do
    before(:each) do
        @href = 'icon href'
        @o = Kamelopard::Icon.new(@href)
        @values = {
            'href' => @href,
            'x' => 1.0,
            'y' => 2.0,
            'w' => 3.0,
            'h' => 4.0,
            'refreshMode' => :onInterval,
            'refreshInterval' => 4,
            'viewRefreshMode' => :onStop,
            'viewRefreshTime' => 4,
            'viewBoundScale' => 1,
            'viewFormat' => 'format',
            'httpQuery' => 'query'
        }
        @fields = @values.keys
    end

    it_should_behave_like 'KML_includes_id'
    it_should_behave_like 'KML_producer'
    it_should_behave_like 'field_producer'

    it 'puts the right fields in KML' do
        @fields.each do |f|
            v = @values[f]
            @o.method("#{f.to_s}=".to_sym).call(v)
            d = @o.to_kml
            elem = f
            if f == 'x' || f == 'y' || f == 'w' || f == 'h' then
                elem = 'gx:' + f
            end
            e = d.elements["//#{elem}"]
            e.should_not be_nil
            e.text.should == v.to_s
        end
    end
end

describe 'Kamelopard::IconStyle' do
    before(:each) do
        @href = 'Kamelopard::IconStyle href'
        @scale = 1.0
        @heading = 2.0
        @hs_x = 0.4
        @hs_y = 0.6
        @hs_xunits = :fraction
        @hs_yunits = :pixels
        @color = 'abcdefab'
        @colorMode = :random
        @o = Kamelopard::IconStyle.new @href, @scale, @heading, @hs_x, @hs_y, @hs_xunits, @hs_yunits, @color, @colorMode
    end

    it_should_behave_like 'Kamelopard::ColorStyle'

    it 'should support the right elements' do
        @o.should respond_to(:scale)
        @o.should respond_to(:scale=)
        @o.should respond_to(:heading)
        @o.should respond_to(:heading=)
    end

    it 'should have the right KML' do
        d = @o.to_kml
        d.elements['//Icon/href'].text.should == @href
        d.elements['//scale'].text.should == @scale.to_s
        d.elements['//heading'].text.should == @heading.to_s
        h = d.elements['//hotSpot']
        h.attributes['x'].should == @hs_x.to_s
        h.attributes['y'].should == @hs_y.to_s
        h.attributes['xunits'].should == @hs_xunits.to_s
        h.attributes['yunits'].should == @hs_yunits.to_s
    end
end

describe 'Kamelopard::LabelStyle' do
    before(:each) do
        @fields = %w[ scale color colorMode ]
        @scale = 2
        @color = 'abcdefab'
        @colorMode = :random
        @o = Kamelopard::LabelStyle.new @scale, @color, @colorMode
    end

    it_should_behave_like 'Kamelopard::ColorStyle'

    it 'should have a scale field' do
        @o.should respond_to(:scale)
        @o.should respond_to(:scale=)
        @o.to_kml.elements['//scale'].text.to_i.should == @scale
    end
end

describe 'Kamelopard::LineStyle' do
    before(:each) do
        @width = 1
        @outerColor = 'aaaaaaaa'
        @outerWidth = 2
        @physicalWidth = 3
        @color = 'abcdefab'
        @colorMode = :normal
        @o = Kamelopard::LineStyle.new @width, @outerColor, @outerWidth, @physicalWidth, @color, @colorMode
        @values = {
            'width' => @width,
            'outerColor' => @outerColor,
            'outerWidth' => @outerWidth,
            'physicalWidth' => @physicalWidth
        }
        @fields = @values.keys
    end

    it_should_behave_like 'Kamelopard::ColorStyle'
    it_should_behave_like 'field_producer'

    it 'should do its KML right' do
        @values.each do |k, v|
            @o.method("#{k}=").call(v)
            elem = (k == 'width' ? k : "gx:#{k}" )
            @o.to_kml.elements["//#{elem}"].text.should == v.to_s
        end
    end
end

describe 'Kamelopard::ListStyle' do
    before(:each) do
        @bgColor = 'ffffffff'
        @state = :closed
        @listItemType = :check
        @href = 'list href'
        @o = Kamelopard::ListStyle.new @bgColor, @state, @href, @listItemType
        @fields = %w[ bgColor state listItemType href ]
    end

    it_should_behave_like 'Kamelopard::Object'
    it_should_behave_like 'KML_includes_id'
    it_should_behave_like 'KML_producer'
    it_should_behave_like 'field_producer'

    it 'makes the right KML' do
        values = {
            'href' => @href,
            'state' => @state,
            'listItemType' => @listItemType,
            'bgColor' => @bgColor
        }
        check_kml_values @o, values
    end
end

describe 'Kamelopard::PolyStyle' do
    before(:each) do
        @fill = 1
        @outline = 1
        @color = 'abcdefab'
        @colorMode = :random
        @o = Kamelopard::PolyStyle.new @fill, @outline, @color, @colorMode
    end

    it_should_behave_like 'Kamelopard::ColorStyle'

    it 'should have the right fields' do
        fields = %w[ fill outline ]
        fields_exist @o, fields
    end

    it 'should do the right KML' do
        values = {
            'fill' => @fill,
            'outline' => @outline
        }
        check_kml_values @o, values
    end
end

describe 'StyleSelector' do
    before(:each) do
        @o = Kamelopard::StyleSelector.new 
    end

    it_should_behave_like 'StyleSelector'
end

describe 'Style' do
    before(:each) do
        i, la, lin, p, b, lis = get_test_substyles
        @o = Kamelopard::Style.new i, la, lin, p, b, lis
    end

    it_should_behave_like 'StyleSelector'

    it 'should have the right attributes' do
        [ :icon, :label, :line, :poly, :balloon, :list ].each do |a|
            @o.should respond_to(a)
            @o.should respond_to("#{ a.to_s }=".to_sym)
        end
    end

    it 'should have the right KML bits' do
        d = @o.to_kml
        %w[ IconStyle LabelStyle LineStyle PolyStyle BalloonStyle ListStyle ].each do |e|
            d.elements["//#{e}"].should_not be_nil
        end
    end
end

describe 'StyleMap' do
    def has_correct_stylemap_kml?(o)
        d = REXML::Document.new o.to_kml.to_s
        return d.elements['/StyleMap/Pair[key="normal"]/Style'] &&
            d.elements['/StyleMap/Pair[key="highlight"]/styleUrl']
    end

    before(:each) do
        i, la, lin, p, b, lis = get_test_substyles
        s = Kamelopard::Style.new i, nil, nil, nil, b, lis
        @o = Kamelopard::StyleMap.new({ 'normal' => s, 'highlight' => 'someUrl' })
    end

    it_should_behave_like 'StyleSelector'

    it 'should handle styles vs. styleurls correctly' do
        has_correct_stylemap_kml?(@o).should be_true
    end

    it 'should merge right' do
        o = Kamelopard::StyleMap.new({ 'normal' => Kamelopard::Style.new(nil, nil, nil, nil, nil, nil) })
        o.merge( { 'highlight' => 'test2' } )
        has_correct_stylemap_kml?(o).should be_true
    end
end

describe 'Kamelopard::Placemark' do
    before(:each) do
        @p = Kamelopard::Point.new(123, 123)
        @o = Kamelopard::Placemark.new 'placemark', @p
    end

    it_should_behave_like 'Kamelopard::Feature'

    it 'supports the right attributes' do
        [
            :latitude,
            :longitude,
            :altitude,
            :altitudeMode
        ].each do |f|
            @o.should respond_to(f)
        end
    end

    it 'handles returning point correctly' do
        o1 = Kamelopard::Placemark.new 'non-point', Kamelopard::Object.new
        o2 = Kamelopard::Placemark.new 'non-point', Kamelopard::Point.new(123, 123)
        lambda { o1.point }.should raise_exception
        lambda { o2.point }.should_not raise_exception
    end
end

describe 'Kamelopard::FlyTo' do
    before(:each) do
        @o = Kamelopard::FlyTo.new 
    end

    it_should_behave_like 'Kamelopard::TourPrimitive'

    it 'puts the right stuff in the KML' do
        duration = 10
        mode = :smooth
        @o.duration = duration
        @o.mode = mode
        @o.to_kml.elements['//gx:duration'].text.should == duration.to_s
        @o.to_kml.elements['//gx:flyToMode'].text.should == mode.to_s
    end

    it 'handles Kamelopard::AbstractView correctly' do
        o = Kamelopard::FlyTo.new Kamelopard::LookAt.new(Kamelopard::Point.new(100, 100))
        o.view.class.should == Kamelopard::LookAt
        o = Kamelopard::FlyTo.new Kamelopard::Point.new(90,90)
        o.view.class.should == Kamelopard::LookAt
        o = Kamelopard::FlyTo.new Kamelopard::Camera.new(Kamelopard::Point.new(90,90))
        o.view.class.should == Kamelopard::Camera
    end
end

describe 'Kamelopard::AnimatedUpdate' do
    before(:each) do
        @duration = 10
        @target = 'abcd'
        @delayedstart = 10
        @o = Kamelopard::AnimatedUpdate.new([], @duration, @target, @delayedstart)
    end

    it_should_behave_like 'Kamelopard::TourPrimitive'

    it 'allows adding updates' do
        @o.updates.size.should == 0
        @o << '<Change><Placemark targetId="1"><visibility>1</visibility></Placemark></Change>'
        @o << '<Change><Placemark targetId="2"><visibility>0</visibility></Placemark></Change>'
        @o.updates.size.should == 2
    end

    it 'returns the right KML' do
        @o.is_a?(Kamelopard::AnimatedUpdate).should == true
        @o << '<Change><Placemark targetId="1"><visibility>1</visibility></Placemark></Change>'
        d = @o.to_kml
        d.elements['//Update/targetHref'].text.should == @target
        d.elements['//Update/Change/Placemark'].should_not be_nil
        d.elements['//gx:delayedStart'].text.to_i.should == @delayedstart
        d.elements['//gx:duration'].text.to_i.should == @duration
    end
end

describe 'Kamelopard::TourControl' do
    before(:each) do
        @o = Kamelopard::TourControl.new
    end

    it_should_behave_like 'Kamelopard::TourPrimitive'

    it 'should have the right KML' do
        @o.to_kml.elements['//gx:playMode'].text.should == 'pause'
    end
end

describe 'Kamelopard::Wait' do
    before(:each) do
        @pause = 10
        @o = Kamelopard::Wait.new(@pause)
    end

    it_should_behave_like 'Kamelopard::TourPrimitive'

    it 'should have the right KML' do
        @o.to_kml.elements['//gx:duration'].text.to_i.should == @pause
    end
end

describe 'Kamelopard::SoundCue' do
    before(:each) do
        @href = 'href'
        @delayedStart = 10.0
        @o = Kamelopard::SoundCue.new @href, @delayedStart
    end

    it_should_behave_like 'Kamelopard::TourPrimitive'

    it 'should have the right KML' do
        d = @o.to_kml
        d.elements['//href'].text.should == @href
        d.elements['//gx:delayedStart'].text.to_f.should == @delayedStart
    end
end

describe 'Kamelopard::Tour' do
    before(:each) do
        @name = 'TourName'
        @description = 'TourDescription'
        @o = Kamelopard::Tour.new @name, @description
        @ns = 'gx'
    end

    it_should_behave_like 'Kamelopard::Object'
    it_should_behave_like 'KML_includes_id'
    it_should_behave_like 'KML_producer'
    it_should_behave_like 'KML_root_name'

    it 'has the right KML' do
        Kamelopard::Wait.new
        Kamelopard::Wait.new
        Kamelopard::Wait.new
        Kamelopard::Wait.new

        d = @o.to_kml
        d.elements['//name'].text.should == @name
        d.elements['//description'].text.should == @description
        p = d.elements['//gx:Playlist']
        p.should_not be_nil
        p.elements.size.should == 4
    end
end

describe 'Kamelopard::ScreenOverlay' do
    before(:each) do
        @x = 10
        @un = :pixel
        @xy = Kamelopard::XY.new @x, @x, @un, @un
        @rotation = 10
        @name = 'some name'
        @o = Kamelopard::ScreenOverlay.new Kamelopard::Icon.new('test'), @name, @xy, @rotation, @xy, @xy, @xy
        @fields = %w[ overlayXY screenXY rotationXY size rotation ]
    end

    it_should_behave_like 'Kamelopard::Overlay'
    it_should_behave_like 'field_producer'

    it 'has the right KML' do
        d = @o.to_kml
        d.elements['//name'].text.should == @name
        d.elements['//rotation'].text.to_i.should == @rotation
        %w[ overlayXY screenXY rotationXY size ].each do |a|
            d.elements["//#{a}"].attributes['x'] = @x
            d.elements["//#{a}"].attributes['y'] = @x
            d.elements["//#{a}"].attributes['xunits'] = @un
            d.elements["//#{a}"].attributes['yunits'] = @un
        end
    end
end

describe 'Kamelopard::ViewVolume' do
    before(:each) do
        @n = 34
        @o = Kamelopard::ViewVolume.new @n, -@n, @n, -@n, @n
        @fields = %w[ leftFov rightFov bottomFov topFov near ]
    end

    it_should_behave_like 'field_producer'
    it_should_behave_like 'KML_root_name'

    it 'has the right KML' do
        d = @o.to_kml
        match_view_vol(d, @n)
    end
end

describe 'Kamelopard::ImagePyramind' do
    before(:each) do
        @n = 34
        @o = Kamelopard::ImagePyramid.new @n, @n, @n, @n
        @fields = %w[ tileSize maxWidth maxHeight gridOrigin ]
    end

    it_should_behave_like 'field_producer'
    it_should_behave_like 'KML_root_name'

    it 'has the right KML' do
        d = @o.to_kml
        match_image_pyramid(d, @n)
    end
end

describe 'Kamelopard::PhotoOverlay' do
    before(:each) do
        @n = 34
        @rotation = 10
        @point = Kamelopard::Point.new(@n, @n)
        @icon = Kamelopard::Icon.new('test')
        @vv = Kamelopard::ViewVolume.new @n, -@n, @n, -@n, @n
        @ip = Kamelopard::ImagePyramid.new @n, @n, @n, @n
        @shape = 'cylinder'
        @o = Kamelopard::PhotoOverlay.new @icon, @point, @rotation, @vv, @ip, @shape
        @fields = %w[ rotation viewvolume imagepyramid point shape ]
    end

    it_should_behave_like 'Kamelopard::Overlay'
    it_should_behave_like 'field_producer'

    it 'has the right KML' do
        d = @o.to_kml
        d.elements['//shape'].text.should == @shape
        d.elements['//rotation'].text.to_i.should == @rotation
        match_view_vol(d.elements['//ViewVolume'], @n).should be_true
        match_image_pyramid(d.elements['//ImagePyramid'], @n).should be_true
    end
end

describe 'Kamelopard::LatLonBox' do
    before(:each) do
        @n = 130.2
        @o = Kamelopard::LatLonBox.new @n, @n, @n, @n, @n, @n, @n, :relativeToGround
        @fields = %w[ north south east west rotation minAltitude maxAltitude altitudeMode ]
    end

    it_should_behave_like 'KML_producer'
    it_should_behave_like 'field_producer'

    it 'has the right KML in altitude mode' do
        d = @o.to_kml(nil, true)
        d.elements['//minAltitude'].text.should == @n.to_s
        d.elements['//maxAltitude'].text.should == @n.to_s
        test_lat_lon_box(d, @o)
    end

    it 'has the right KML in non-altitude mode' do
        d = @o.to_kml(nil, false)
        test_lat_lon_box(d, @o)
    end
end

describe 'Kamelopard::LatLonQuad' do
    before(:each) do
        @n = 123.2
        @p = Kamelopard::Point.new @n, @n
        @o = Kamelopard::LatLonQuad.new @p, @p, @p, @p
        @fields = %w[ lowerLeft lowerRight upperRight upperLeft ]
    end

    it_should_behave_like 'KML_producer'
    it_should_behave_like 'field_producer'

    it 'has the right KML' do
        d = @o.to_kml
        test_lat_lon_quad(d, @n)
    end
end

describe 'Kamelopard::GroundOverlay' do
    before(:each) do
        @icon_href = 'some href'
        @i = Kamelopard::Icon.new @icon_href
        @n = 123.2
        @lb = Kamelopard::LatLonBox.new @n, @n, @n, @n, @n, @n, @n, :relativeToGround
        @p = Kamelopard::Point.new @n, @n
        @lq = Kamelopard::LatLonQuad.new @p, @p, @p, @p
        @altmode = :relativeToSeaFloor
        @o = Kamelopard::GroundOverlay.new @i, @lb, @lq, @n, @altmode
        @fields = %w[ altitude altitudeMode latlonbox latlonquad ]
    end

    it_should_behave_like 'Kamelopard::Overlay'
    it_should_behave_like 'field_producer'
    it_should_behave_like 'altitudeMode'
    it_should_behave_like 'KML_root_name'

    it 'complains when latlonbox and latlonquad are nil' do
        o = Kamelopard::GroundOverlay.new @i, nil, nil, @n, @altmode
        lambda { o.to_kml }.should raise_exception
        o.latlonquad = @lq
        lambda { o.to_kml }.should_not raise_exception
    end

    it 'has the right KML' do
        d = @o.to_kml
        d.elements['//altitude'].text.should == @n.to_s
        test_lat_lon_box(d, @lb)
        test_lat_lon_quad(d, @n)
    end
end

describe 'Kamelopard::Lod' do
    before(:each) do
        @n = 324
        @o = Kamelopard::Lod.new @n, @n, @n, @n
        @fields = %w[ minpixels maxpixels minfade maxfade ]
    end

    it_should_behave_like 'field_producer'
    it_should_behave_like 'KML_root_name'

    it 'has the right KML' do
        d = @o.to_kml
        test_lod d, @n
    end
end

describe 'Kamelopard::Region' do
    before(:each) do
        @n = 12
        @lb = Kamelopard::LatLonBox.new @n, @n, @n, @n, @n, @n, @n, :relativeToGround
        @ld = Kamelopard::Lod.new @n, @n, @n, @n
        @o = Kamelopard::Region.new @lb, @ld
        @fields = %w[ latlonaltbox lod ]
    end

    it_should_behave_like 'Kamelopard::Object'
    it_should_behave_like 'field_producer'
    it_should_behave_like 'KML_root_name'

    it 'has the right KML' do
        d = @o.to_kml
        test_lat_lon_box(d.elements['//LatLonAltBox'], @lb)
        test_lod(d.elements['//Lod'], @n)
    end
end

describe 'Kamelopard::Orientation' do
    before(:each) do
        @n = 37
        @o = Kamelopard::Orientation.new @n, @n, @n
        @fields = %w[ heading tilt roll ]
    end

    it_should_behave_like 'KML_producer'
    it_should_behave_like 'field_producer'
    it_should_behave_like 'KML_root_name'

#    it 'should complain with weird arguments' do
#        lambda { Kamelopard::Orientation.new -1, @n, @n }.should raise_exception
#        lambda { Kamelopard::Orientation.new @n, -1, @n }.should raise_exception
#        lambda { Kamelopard::Orientation.new @n, @n, -1 }.should raise_exception
#        lambda { Kamelopard::Orientation.new 483, @n,  @n }.should raise_exception
#        lambda { Kamelopard::Orientation.new @n,  483, @n }.should raise_exception
#        lambda { Kamelopard::Orientation.new @n,  @n,  483 }.should raise_exception
#    end

    it 'has the right KML' do
        d = @o.to_kml
        @fields.each do |f|
            d.elements["//#{f}"].text.to_i.should == @n
        end
    end
end

describe 'Kamelopard::Scale' do
    before(:each) do
        @n = 213
        @o = Kamelopard::Scale.new @n, @n, @n
        @fields = %w[ x y z ]
    end

    it_should_behave_like 'KML_producer'
    it_should_behave_like 'field_producer'
    it_should_behave_like 'KML_root_name'

    it 'has the right KML' do
        d = @o.to_kml
        @fields.each do |f|
            d.elements["//#{f}"].text.to_i.should == @n
        end
    end
end

describe 'Kamelopard::Alias' do
    before(:each) do
        @n = 'some href'
        @o = Kamelopard::Alias.new @n, @n
        @fields = %w[ targetHref sourceHref ]
    end

    it_should_behave_like 'KML_producer'
    it_should_behave_like 'field_producer'
    it_should_behave_like 'KML_root_name'

    it 'has the right KML' do
        d = @o.to_kml
        @fields.each do |f|
            d.elements["//#{f}"].text.should == @n
        end
    end
end

describe 'Kamelopard::ResourceMap' do
    before(:each) do
        targets = %w[ Neque porro quisquam est qui  dolorem     ipsum      quia dolor sit  amet consectetur adipisci velit ]
        sources = %w[ Lorem ipsum dolor    sit amet consectetur adipiscing elit Nunc  quis odio metus       Fusce    at    ]
        @aliases = []
        targets.zip(sources).each do |a|
            @aliases << Kamelopard::Alias.new(a[0], a[1])
        end
        @o = Kamelopard::ResourceMap.new @aliases
        @fields = [ 'aliases' ]
    end

    it_should_behave_like 'KML_producer'
    it_should_behave_like 'field_producer'
    it_should_behave_like 'KML_root_name'

    it 'accepts various aliases correctly' do
        # ResourceMap should accept its initializer's alias argument either as
        # an array of Alias object, or as a single Alias object. The
        # before(:each) block tests the former, and this test the latter
        o = Kamelopard::ResourceMap.new Kamelopard::Alias.new('test', 'test')
        o.aliases.size.should == 1
        @o.aliases.size.should == @aliases.size
    end

    it 'has the right KML' do
        # Make this a REXML::Document instead of just a collection of elements, for better XPath support
        d = REXML::Document.new
        d << @o.to_kml
        @aliases.each do |a|
            d.elements["//Alias[targetHref=\"#{a.targetHref}\" and sourceHref=\"#{a.sourceHref}\"]"].should_not be_nil
        end
    end
end

describe 'Kamelopard::Link' do
    before(:each) do
        @href = 'some href'
        @refreshMode = :onInterval
        @viewRefreshMode = :onRegion
        @o = Kamelopard::Link.new @href, @refreshMode, @viewRefreshMode
        @fields = %w[ href refreshMode refreshInterval viewRefreshMode viewBoundScale viewFormat httpQuery ]
    end

    it_should_behave_like 'Kamelopard::Object'
    it_should_behave_like 'KML_producer'
    it_should_behave_like 'field_producer'
    it_should_behave_like 'KML_root_name'

    it 'has the right KML' do
        @n = 213
        @o.refreshInterval = @n
        @o.viewBoundScale = @n 
        @o.viewFormat = @href
        @o.httpQuery = @href
        d = @o.to_kml
        {
            :href => @href,
            :refreshMode => @refreshMode,
            :refreshInterval => @n,
            :viewRefreshMode => @viewRefreshMode,
            :viewBoundScale => @n,
            :viewFormat => @href,
            :httpQuery => @href
        }.each do |k, v|
            d.elements["//#{k}"].text.should == v.to_s
        end
    end
end

describe 'Kamelopard::Model' do
    before(:each) do
        @n = 123
        @href = 'some href'
        @refreshMode = :onInterval
        @viewRefreshMode = :onRegion
        @link = Kamelopard::Link.new @href, @refreshMode, @viewRefreshMode
        @loc = Kamelopard::Point.new @n, @n, @n
        @orient = Kamelopard::Orientation.new @n, @n, @n
        @scale = Kamelopard::Scale.new @n, @n, @n
        targets = %w[ Neque porro quisquam est qui  dolorem     ipsum      quia dolor sit  amet consectetur adipisci velit ]
        sources = %w[ Lorem ipsum dolor    sit amet consectetur adipiscing elit Nunc  quis odio metus       Fusce    at    ]
        @aliases = []
        targets.zip(sources).each do |a|
            @aliases << Kamelopard::Alias.new(a[0], a[1])
        end
        @resmap = Kamelopard::ResourceMap.new @aliases
        @o = Kamelopard::Model.new @link, @loc, @orient, @scale, @resmap
        @fields = %w[ link location orientation scale resourceMap ]
    end

    it_should_behave_like 'Kamelopard::Geometry'
    it_should_behave_like 'KML_producer'
    it_should_behave_like 'field_producer'

    it 'makes the right KML' do
        d = REXML::Document.new
        d << @o.to_kml
        %w[ Link Location Orientation Scale ResourceMap ].each do |f|
            d.elements["//#{f}"].should_not be_nil
        end
        %w[ longitude latitude altitude ].each do |f|
            d.elements["//Location/#{f}"].text.to_i.should == @n
        end
    end
end

describe 'Kamelopard::Container' do
    before(:each) do
        @o = Kamelopard::Container.new()
    end

    it_should_behave_like 'Kamelopard::Container' 
end
