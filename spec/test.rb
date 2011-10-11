# vim:ts=4:sw=4:et:smartindent:nowrap
$LOAD_PATH << './lib'
require 'kamelopard'
require 'rexml/document'

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

def validate_abstractview(k, type, point, heading, tilt, roll, range, mode)
    [
        [ k.root.name != type, "Wrong type #{ k.root.name }" ],
        [ k.elements['//longitude'].text.to_f != point.longitude, 'Wrong longitude' ],
        [ k.elements['//longitude'].text.to_f != point.longitude, 'Wrong longitude' ],
        [ k.elements['//latitude'].text.to_f != point.latitude, 'Wrong latitude' ],
        [ k.elements['//altitude'].text.to_f != point.altitude, 'Wrong altitude' ],
        [ k.elements['//heading'].text.to_f != heading, 'Wrong heading' ],
        [ k.elements['//tilt'].text.to_f != tilt, 'Wrong tilt' ],
        [ type == 'LookAt' && k.elements['//range'].text.to_f != range, 'Wrong range' ],
        [ type == 'Camera' && k.elements['//roll'].text.to_f != roll, 'Wrong roll' ],
        [ mode !~ /SeaFloor/ && k.elements['//altitudeMode'] != mode.to_s, 'Wrong altitude mode' ],
        [ mode =~ /SeaFloor/ && k.elements['//gx:altitudeMode'] != mode.to_s, 'Wrong gx:altitudeMode' ]
    ].each do |a|
        return [false, a[1]] if a[0]
    end
end

def get_test_substyles()
    i = IconStyle.new 'icon'
    la = LabelStyle.new
    lin = LineStyle.new
    p = PolyStyle.new
    b = BalloonStyle.new 'balloon'
    lis = ListStyle.new
    [ i, la, lin, p, b, lis ]
end

def get_test_styles()
    i, la, lin, p, b, lis = get_test_substyles()
    
    si = Style.new i
    sl = Style.new i, la, lin, p, b, lis
    sm = StyleMap.new( { :icon => si, :list => sl } )
    
    si.id = 'icon'
    sl.id = 'list'
    sm.id = 'map'

    [ si, sl, sm ]
end

def check_time_primitive(set_var_lambda, get_kml_lambda, xpath)
    b = '2011-01-01'
    e = '2011-02-01'
    w = '2011-01-01'
    tn = TimeSpan.new(b, e)
    tm = TimeStamp.new(w)

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

shared_examples_for 'KMLObject' do
    it 'descends from KMLObject' do
        @o.kind_of?(KMLObject).should == true
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

shared_examples_for 'Geometry' do
    it_should_behave_like 'KMLObject'

    it 'descends from Geometry' do
        @o.kind_of?(Geometry).should == true
    end
end

shared_examples_for 'AbstractView' do
    it_should_behave_like 'KMLObject'
    it_should_behave_like 'altitudeMode'
    it_should_behave_like 'KML_includes_id'
    it_should_behave_like 'KML_producer'

    it 'descends from AbstractView' do
        @o.kind_of?(AbstractView).should == true
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
 
shared_examples_for 'CoordinateList' do
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

        it 'accepts KMLPoints' do
            @o << KMLPoint.new(3,2,1)
        end

        it 'accepts arrays of points' do
            q = []
            [[1,2,3], [2,3,4], [3,4,5]].each do |a|
                q << KMLPoint.new(a[0], a[1], a[2])
            end
            @o << q
        end

        it 'accepts another CoordinateList' do
            p = CoordinateList.new( [[1,2,3], [2,3,4], [3,4,5]] )
            @o << p
        end

        it 'complains when trying to add something weird' do
            a = REXML::Document.new('<a>b</a>')
            lambda { @o << a }.should raise_error
        end
    end

end

shared_examples_for 'Camera-like' do
    it_should_behave_like 'AbstractView'

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

shared_examples_for "TimePrimitive" do
    it_should_behave_like 'KMLObject'
    it_should_behave_like 'KML_producer'
    it_should_behave_like 'KML_includes_id'

    it 'descends from TimePrimitive' do
        @o.kind_of?(TimePrimitive).should == true
    end
end

shared_examples_for 'Feature' do
    def document_has_styles(d)
        si = d.elements['//Style[@id="icon"]']
        STDERR.puts @o.class if si.nil?
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

    it_should_behave_like 'KMLObject'
    it_should_behave_like 'KML_includes_id'
    it_should_behave_like 'KML_producer'

    it 'descends from Feature' do
        @o.kind_of?(Feature).should == true
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
        k = get_kml
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
            p = Feature.new()
            Document.instance.folder << p
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
            p = Feature.new()
            p.instance_variable_set(a[0], marker)
            e = p.to_kml.elements["//#{a[1]}"]
            e.should_not be_nil
            e.text.should == marker
        end
    end

    it 'correctly KML-ifies the atom:author field' do
        o = Feature.new()
        marker = 'Look for this text'
        o.atom_author = marker
        o.to_kml.elements['//atom:author/atom:name'].text.should == marker
    end

    it 'returns the right KML for boolean fields' do
        %w( visibility open ).each do |k|
            [false, true].each do |v|
                o = Feature.new()
                o.instance_variable_set("@#{k}".to_sym, v)
                o.to_kml.elements["//#{k}"].text.to_i.should == (v ? 1 : 0)
            end
        end
    end

    it 'correctly KML\'s the Snippet' do
        maxlines = 2
        text = "This is my snippet\nIt's more than two lines long.\nNo, really."
        @o.snippet = Snippet.new(text, maxlines)
        s = @o.to_kml.elements["//Snippet[@maxLines='#{ maxlines }']"]
        s.should_not be_nil
        s.text.should == text
    end

    describe 'correctly produces Region KML' do
        before(:all) do
            @o = Feature.new('my feature')
            @latlon = LatLonBox.new( 1, -1, 1, -1, 10 )
            @lod = Lod.new(128, 1024, 128, 128)
            @r = Region.new(@latlon, @lod)
            @o.region = @r

            @reg = @o.to_kml.elements['//Region']
            @l = @reg.elements['LatLonAltBox']
            @ld = @reg.elements['Lod']
        end

        it 'creates a Region element' do
            @reg.should_not be_nil
            @reg.attributes['id'].should == @r.id
        end

        it 'creates the right LatLonAltBox' do 
            @l.should_not be_nil
            @l.elements['north'].text.should == @latlon.north.to_s
            @l.elements['south'].text.should == @latlon.south.to_s
            @l.elements['east'].text.should == @latlon.east.to_s
            @l.elements['west'].text.should == @latlon.west.to_s
        end

        it 'creates the right LOD' do
            @ld.should_not be_nil
            @ld.elements['minLodPixels'].text.should == @lod.minpixels.to_s
            @ld.elements['maxLodPixels'].text.should == @lod.maxpixels.to_s
            @ld.elements['minFadeExtent'].text.should == @lod.minfade.to_s
            @ld.elements['maxFadeExtent'].text.should == @lod.maxfade.to_s
        end

    end

    it 'correctly KML\'s the StyleSelector' do
        @o = Feature.new 'StyleSelector test'
        get_test_styles.each do |s| @o.styles << s end
        document_has_styles(@o.to_kml).should == true
    end

    it 'correctly KML\'s the TimePrimitive' do
        check_time_primitive(
            lambda { |t| @o.timeprimitive = t },
            lambda { @o.to_kml },
            ''
        )
    end

    it 'correctly KML\'s the AbstractView' do
        long, lat, alt = 13, 12, 11
        heading, tilt, roll, range, mode = 1, 2, 3, 4, :clampToSeaFloor
        p = KMLPoint.new(long, lat, alt)
        camera = Camera.new p, heading, tilt, roll
        lookat = LookAt.new p, heading, tilt, range
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

shared_examples_for 'Container' do
    it 'should handle <<' do
        @o.should respond_to('<<')
    end
end

shared_examples_for 'ColorStyle' do
    it_should_behave_like 'KMLObject'
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
    it_should_behave_like 'KMLObject'
    it_should_behave_like 'KML_producer'
    it_should_behave_like 'KML_includes_id'

    it 'should handle being attached to stuff' do
        @o.should respond_to(:attach)
        p = Placemark.new KMLPoint.new(123, 23), 'test'
        @o.attach(p)
        @o.attached?.should be_true
    end
end

shared_examples_for 'TourPrimitive' do
    it_should_behave_like 'KMLObject'
end

describe 'KMLObject' do
    before(:each) do
        @o = KMLObject.new()
    end

    it_should_behave_like 'KMLObject'
    it_should_behave_like 'KML_producer'
end

describe 'KMLPoint' do
    before(:each) do
        @attrs = { :lat => 12.4, :long => 34.2, :alt => 500 }
        @fields = %w[ latitude longitude altitude ]
        @o = KMLPoint.new @attrs[:long], @attrs[:lat], @attrs[:alt]
    end

    it_should_behave_like 'KML_includes_id'
    it_should_behave_like 'Geometry'

    it 'accepts different coordinate formats' do
        coords = [ [ '123D30m12.2s S', '34D56m24.4s E' ],
                   [ '32d10\'23.10" N', -145.3487 ],
                   [ 123.5985745,      -45.32487 ] ]
        coords.each do |a|
            lambda { KMLPoint.new a[1], a[0] }.should_not raise_error
        end
    end

    it 'does not accept coordinates that are out of range' do
        q = ''
        begin
            KMLPoint.new 342.32487, 45908.123487
        rescue RuntimeError => f
            q = f.to_s
        end
        q.should =~ /out of range/
    end

    it 'has the right attributes' do
        fields = %w[ latitude longitude altitude altitudeMode extrude ]
        fields_exist @o, fields
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

describe 'CoordinateList' do
    before(:each) do
        @o = CoordinateList.new
    end

    it_should_behave_like 'KML_producer'

    it 'has the right attributes and methods' do
        @o.should respond_to(:coordinates)
        @o.should respond_to(:<<)
        @o.should respond_to(:add_element)
    end

    it_should_behave_like 'CoordinateList'
end

describe 'LineString' do
    before(:each) do
        @o = LineString.new([ [1,2,3], [2,3,4], [3,4,5] ])
    end

    it_should_behave_like 'altitudeMode'
    it_should_behave_like 'KML_includes_id'
    it_should_behave_like 'KML_producer'
    it_should_behave_like 'Geometry'
    it_should_behave_like 'CoordinateList'

    it 'has the right attributes' do
        fields = %w[
            altitudeOffset extrude tessellate altitudeMode
            drawOrder longitude latitude altitude
        ]
        fields_exist @o, fields
    end

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

describe 'LinearRing' do
    before(:each) do
        @o = LinearRing.new([ [1,2,3], [2,3,4], [3,4,5] ])
    end

    it_should_behave_like 'altitudeMode'
    it_should_behave_like 'KML_includes_id'
    it_should_behave_like 'KML_producer'
    it_should_behave_like 'Geometry'
    it_should_behave_like 'CoordinateList'

    it 'has the right attributes' do
        fields = %w[ altitudeOffset extrude tessellate altitudeMode ]
        fields_exist @o, fields
    end

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

describe 'Camera' do
    before(:each) do
        @o = Camera.new KMLPoint.new(123, -123, 123), 10, 10, 10, :clampToGround
        @fields = [ 'roll' ]
    end

    it_should_behave_like 'Camera-like'

    it 'contains the right KML attributes' do
        @o.roll = 12
        k = @o.to_kml
        k.elements['//roll]'].text.should == '12'
    end
end

describe 'LookAt' do
    before(:each) do
        @o = LookAt.new KMLPoint.new(123, -123, 123), 10, 10, 10, :clampToGround
        @fields = [ 'range' ]
    end

    it_should_behave_like 'Camera-like'
    it 'contains the right KML attributes' do
        @o.range = 10
        k = @o.to_kml
        k.root.name.should == 'LookAt'
        k.elements['[range=10]'].should_not be_nil
    end
end

describe 'TimeStamp' do
    before(:each) do
        @when = '01 Dec 1934 12:12:12 PM'
        @o = TimeStamp.new @when
    end

    it_should_behave_like 'TimePrimitive'

    it 'has the right attributes' do
        @o.should respond_to(:when)
        @o.should respond_to(:when=)
    end

    it 'has the right KML elements' do
        k = @o.to_kml
        k.root.name.should == 'TimeStamp'
        k.elements["[when='#{ @when }']"].should_not be_nil
    end
end

describe 'TimeSpan' do
    before(:each) do
        @begin = '01 Dec 1934 12:12:12 PM'
        @end = '02 Dec 1934 12:12:12 PM'
        @o = TimeSpan.new @begin, @end
    end

    it_should_behave_like 'TimePrimitive'

    it 'has the right attributes' do
        fields = %w[ begin end ]
        fields_exist @o, fields
    end

    it 'has the right KML elements' do
        k = @o.to_kml
        k.root.name.should == 'TimeSpan'
        k.elements["[begin='#{ @begin }']"].should_not be_nil
        k.elements["[end='#{ @end }']"].should_not be_nil
    end
end

describe 'Feature' do
    before(:each) do
        @o = Feature.new('Some feature')
        @fields = []
    end

    it_should_behave_like 'Feature'
end

describe 'Container' do
    before(:each) do
        @o = Container.new
    end

    it_should_behave_like 'Container'
end

describe 'Folder' do
    before(:each) do
        @o = Folder.new('test folder')
        @fields = []
    end
    it_should_behave_like 'Container'
    it_should_behave_like 'Feature'
end

describe 'Document' do
    before(:each) do
        @o = Document.instance
        @fields = []
    end

    it_should_behave_like 'Container'
    it_should_behave_like 'Feature'

    it 'should return a tour' do
        @o.should respond_to(:tour)
        @o.tour.class.should == Tour
    end

    it 'should return a folder' do
        @o.should respond_to(:folder)
        @o.folder.class.should == Folder
    end

    it 'should have a get_kml_document method' do
        @o.should respond_to(:get_kml_document)
        @o.get_kml_document.class.should == REXML::Document
    end
end

describe 'ColorStyle' do
    before(:each) do
        @o = ColorStyle.new 'ffffffff'
    end

    it_should_behave_like 'ColorStyle'

    it 'should return the right KML' do
        @o.color = 'deadbeef'
        @o.colorMode = :random
        d = @o.to_kml
        d.root.name.should == 'ColorStyle'
        d.elements['//color'].text.should == 'deadbeef'
        d.elements['//colorMode'].text.should == 'random'
    end
end

describe 'BalloonStyle' do
    before(:each) do
        @o = BalloonStyle.new 'balloon text'
        @o.textColor = 'deadbeef'
        @o.bgColor = 'deadbeef'
        @o.displayMode = :hide
    end

    it_should_behave_like 'KMLObject'
    it_should_behave_like 'KML_includes_id'
    it_should_behave_like 'KML_producer'

    it 'should have the right attributes' do
        @o.bgColor.should == 'deadbeef'
        @o.textColor.should == 'deadbeef'
        @o.displayMode.should == :hide
    end

    it 'should return the right KML' do
        s = @o.to_kml
        s.root.name.should == 'BalloonStyle'
        s.elements['//text'].text.should == 'balloon text'
        s.elements['//bgColor'].text.should == 'deadbeef'
        s.elements['//textColor'].text.should == 'deadbeef'
        s.elements['//displayMode'].text.should == 'hide'
    end
end

describe 'KMLxy' do
    before(:each) do
        @x, @y, @xunits, @yunits = 0.2, 13, :fraction, :pixels
        @o = KMLxy.new @x, @y, @xunits, @yunits
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

describe 'Icon' do
    before(:each) do
        @href = 'icon href'
        @o = Icon.new(@href)
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

    it 'has the right attributes' do
        fields_exist @o, @fields
    end

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

describe 'IconStyle' do
    before(:each) do
        @href = 'IconStyle href'
        @scale = 1.0
        @heading = 2.0
        @hs_x = 0.4
        @hs_y = 0.6
        @hs_xunits = :fraction
        @hs_yunits = :pixels
        @color = 'abcdefab'
        @colorMode = :random
        @o = IconStyle.new @href, @scale, @heading, @hs_x, @hs_y, @hs_xunits, @hs_yunits, @color, @colorMode
    end

    it_should_behave_like 'ColorStyle'

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

describe 'LabelStyle' do
    before(:each) do
        @fields = %w[ scale color colorMode ]
        @scale = 2
        @color = 'abcdefab'
        @colorMode = :random
        @o = LabelStyle.new @scale, @color, @colorMode
    end

    it_should_behave_like 'ColorStyle'

    it 'should have a scale field' do
        @o.should respond_to(:scale)
        @o.should respond_to(:scale=)
        @o.to_kml.elements['//scale'].text.to_i.should == @scale
    end
end

describe 'LineStyle' do
    before(:each) do
        @width = 1
        @outerColor = 'aaaaaaaa'
        @outerWidth = 2
        @physicalWidth = 3
        @color = 'abcdefab'
        @colorMode = :normal
        @o = LineStyle.new @width, @outerColor, @outerWidth, @physicalWidth, @color, @colorMode
        @values = {
            'width' => @width,
            'outerColor' => @outerColor,
            'outerWidth' => @outerWidth,
            'physicalWidth' => @physicalWidth
        }
        @fields = @values.keys
    end

    it_should_behave_like 'ColorStyle'

    it 'should do its KML right' do
        @values.each do |k, v|
            @o.method("#{k}=").call(v)
            elem = (k == 'width' ? k : "gx:#{k}" )
            @o.to_kml.elements["//#{elem}"].text.should == v.to_s
        end
    end
end

describe 'ListStyle' do
    before(:each) do
        @bgColor = 'ffffffff'
        @state = :closed
        @listItemType = :check
        @href = 'list href'
        @o = ListStyle.new @bgColor, @state, @href, @listItemType
    end

    it_should_behave_like 'KMLObject'
    it_should_behave_like 'KML_includes_id'
    it_should_behave_like 'KML_producer'

    it 'has the right fields' do
        fields = %w[ bgColor state listItemType href ]
        fields_exist @o, fields
    end

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

describe 'PolyStyle' do
    before(:each) do
        @fill = 1
        @outline = 1
        @color = 'abcdefab'
        @colorMode = :random
        @o = PolyStyle.new @fill, @outline, @color, @colorMode
    end

    it_should_behave_like 'ColorStyle'

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
        @o = StyleSelector.new 
    end

    it_should_behave_like 'StyleSelector'
end

describe 'Style' do
    before(:each) do
        i, la, lin, p, b, lis = get_test_substyles
        @o = Style.new i, la, lin, p, b, lis
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
        s = Style.new i, nil, nil, nil, b, lis
        @o = StyleMap.new({ 'normal' => s, 'highlight' => 'someUrl' })
    end

    it_should_behave_like 'StyleSelector'

    it 'should handle styles vs. styleurls correctly' do
        has_correct_stylemap_kml?(@o).should be_true
    end

    it 'should merge right' do
        o = StyleMap.new({ 'normal' => Style.new(nil, nil, nil, nil, nil, nil) })
        o.merge( { 'highlight' => 'test2' } )
        has_correct_stylemap_kml?(o).should be_true
    end
end

describe 'Placemark' do
    before(:each) do
        @p = KMLPoint.new(123, 123)
        @o = Placemark.new 'placemark', @p
    end

    it_should_behave_like 'Feature'

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
        o1 = Placemark.new 'non-point', KMLObject.new
        o2 = Placemark.new 'non-point', KMLPoint.new(123, 123)
        lambda { o1.point }.should raise_exception
        lambda { o2.point }.should_not raise_exception
    end
end

describe 'FlyTo' do
    before(:each) do
        @o = FlyTo.new 
    end

    it_should_behave_like 'TourPrimitive'

    it 'puts the right stuff in the KML' do
        duration = 10
        mode = :smooth
        @o.duration = duration
        @o.mode = mode
        @o.to_kml.elements['//gx:duration'].text.should == duration.to_s
        @o.to_kml.elements['//gx:flyToMode'].text.should == mode.to_s
    end

    it 'handles AbstractView correctly' do
        o = FlyTo.new LookAt.new(KMLPoint.new(100, 100))
        o.view.class.should == LookAt
        o = FlyTo.new KMLPoint.new(90,90)
        o.view.class.should == LookAt
        o = FlyTo.new Camera.new(KMLPoint.new(90,90))
        o.view.class.should == Camera
    end
end
