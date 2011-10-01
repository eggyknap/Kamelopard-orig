# vim:ts=4:sw=4:et:smartindent:nowrap
$LOAD_PATH << './lib'
require 'kamelopard'
require 'rexml/document'

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

def get_test_styles()
    si = Style.new IconStyle.new('')
    sl = Style.new nil, nil, nil, nil, nil, ListStyle.new()
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

    it 'has the right attributes' do
        @o.should respond_to(:timestamp)
        @o.should respond_to(:timespan)
        @o.should respond_to(:options)
        @o.should respond_to(:timestamp=)
        @o.should respond_to(:timespan=)
        @o.should respond_to(:options=)
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
        @o.should respond_to(:longitude)
        @o.should respond_to(:latitude)
        @o.should respond_to(:altitude)
        @o.should respond_to(:heading)
        @o.should respond_to(:tilt)
        @o.should respond_to(:roll)
        @o.should respond_to(:altitudeMode)
        @o.should respond_to(:longitude=)
        @o.should respond_to(:latitude=)
        @o.should respond_to(:altitude=)
        @o.should respond_to(:heading=)
        @o.should respond_to(:tilt=)
        @o.should respond_to(:roll=)
        @o.should respond_to(:altitudeMode=)
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
        @o.should respond_to(:visibility=)
        @o.should respond_to(:open=)
        @o.should respond_to(:atom_author=)
        @o.should respond_to(:atom_link=)
        @o.should respond_to(:name=)
        @o.should respond_to(:phoneNumber=)
        @o.should respond_to(:snippet=)
        @o.should respond_to(:description=)
        @o.should respond_to(:abstractView=)
        @o.should respond_to(:timestamp=)
        @o.should respond_to(:timespan=)
        @o.should respond_to(:styleUrl=)
        @o.should respond_to(:styleSelector=)
        @o.should respond_to(:region=)
        @o.should respond_to(:metadata=)
        @o.should respond_to(:extendedData=)
        @o.should respond_to(:styles=)

        @o.should respond_to(:visibility)
        @o.should respond_to(:open)
        @o.should respond_to(:atom_author)
        @o.should respond_to(:atom_link)
        @o.should respond_to(:name)
        @o.should respond_to(:phoneNumber)
        @o.should respond_to(:snippet)
        @o.should respond_to(:description)
        @o.should respond_to(:abstractView)
        @o.should respond_to(:timestamp)
        @o.should respond_to(:timespan)
        @o.should respond_to(:styleUrl)
        @o.should respond_to(:styleSelector)
        @o.should respond_to(:region)
        @o.should respond_to(:metadata)
        @o.should respond_to(:extendedData)
        @o.should respond_to(:styles)

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
        @o.should respond_to(:latitude)
        @o.should respond_to(:latitude=)
        @o.should respond_to(:longitude)
        @o.should respond_to(:longitude=)
        @o.should respond_to(:altitude)
        @o.should respond_to(:altitude=)
        @o.should respond_to(:altitudeMode)
        @o.should respond_to(:altitudeMode=)
        @o.should respond_to(:extrude)
        @o.should respond_to(:extrude=)
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
        @o.should respond_to(:altitudeOffset)
        @o.should respond_to(:extrude)
        @o.should respond_to(:tessellate)
        @o.should respond_to(:altitudeMode)
        @o.should respond_to(:drawOrder)
        @o.should respond_to(:longitude)
        @o.should respond_to(:latitude)
        @o.should respond_to(:altitude)
        @o.should respond_to(:altitudeOffset=)
        @o.should respond_to(:extrude=)
        @o.should respond_to(:tessellate=)
        @o.should respond_to(:altitudeMode=)
        @o.should respond_to(:drawOrder=)
        @o.should respond_to(:longitude=)
        @o.should respond_to(:latitude=)
        @o.should respond_to(:altitude=)
        @o.should respond_to(:coordinates)
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
        @o.should respond_to(:altitudeOffset)
        @o.should respond_to(:extrude)
        @o.should respond_to(:tessellate)
        @o.should respond_to(:altitudeMode)
        @o.should respond_to(:extrude=)
        @o.should respond_to(:tessellate=)
        @o.should respond_to(:altitudeMode=)
        @o.should respond_to(:coordinates)
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
        @o.should respond_to(:begin)
        @o.should respond_to(:begin=)
        @o.should respond_to(:end)
        @o.should respond_to(:end=)
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
    end
    it_should_behave_like 'Container'
    it_should_behave_like 'Feature'
end

describe 'Document' do
    before(:each) do
        @o = Document.instance
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
