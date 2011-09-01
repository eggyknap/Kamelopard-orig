# vim:ts=4:sw=4:et:smartindent:nowrap
$LOAD_PATH << './lib'
require 'kamelopard'
require 'rexml/document'

shared_examples_for 'KMLObject' do
    it 'descends from KMLObject' do
        a = @o.kind_of? KMLObject
        a.should == true
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
        k.should =~ /<!-- Look for this string -->/
    end
end

shared_examples_for 'altitudeMode' do
    it 'uses the right altitudeMode element' do
        @o.altitudeMode = :absolute
        @o.to_kml.should =~ /<altitudeMode>absolute<\/altitudeMode>/
        @o.altitudeMode = :clampToGround
        @o.to_kml.should =~ /<altitudeMode>clampToGround<\/altitudeMode>/
        @o.altitudeMode = :relativeToGround
        @o.to_kml.should =~ /<altitudeMode>relativeToGround<\/altitudeMode>/

        @o.altitudeMode = :clampToSeaFloor
        @o.to_kml.should =~ /<gx:altitudeMode>clampToSeaFloor<\/gx:altitudeMode>/
        @o.altitudeMode = :relativeToSeaFloor
        @o.to_kml.should =~ /<gx:altitudeMode>relativeToSeaFloor<\/gx:altitudeMode>/
    end
end

shared_examples_for 'KML_includes_id' do
    it 'should include the object ID in the KML' do
        k = @o.to_kml
        d = REXML::Document.new k
        d.root.attributes['id'].should_not be_nil
    end
end

shared_examples_for 'KML_producer' do
    it 'should produce KML' do
        @o.should respond_to(:to_kml)
        # Make sure it doesn't barf when passing an indent value
        @o.to_kml(14)
    end
end

shared_examples_for 'Geometry' do
    it_should_behave_like 'KMLObject'

    it 'descends from Geometry' do
        a = @o.kind_of? Geometry
        a.should == true
    end
end

shared_examples_for 'AbstractView' do
    it_should_behave_like 'KMLObject'
    it_should_behave_like 'altitudeMode'
    it_should_behave_like 'KML_includes_id'
    it_should_behave_like 'KML_producer'

    it 'descends from AbstractView' do
        a = @o.kind_of? AbstractView
        a.should == true
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
        k.should =~ /ViewerOptions/
        k.should =~ /"sunlight" enabled="true"/
        k.should =~ /"streetview" enabled="true"/
        k.should =~ /"historicalimagery" enabled="true"/

        @o[:streetview] = false
        @o[:sunlight] = false
        @o[:historicalimagery] = false
        k = @o.to_kml
        k.should =~ /ViewerOptions/
        k.should =~ /"sunlight" enabled="false"/
        k.should =~ /"streetview" enabled="false"/
        k.should =~ /"historicalimagery" enabled="false"/
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
        k.should =~ /<coordinates>\n.*\n\s*<\/coordinates>/
        k.should =~ /1.0,2.0,3.0/
        k.should =~ /2.0,3.0,4.0/
        k.should =~ /3.0,4.0,5.0/
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
        k.should =~ /<longitude>/
        k.should =~ /<latitude>/
        k.should =~ /<altitude>/
        k.should =~ /<heading>/
        k.should =~ /<tilt>/
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
            k.should =~ /<coordinates>#{ @attrs[:long] }, #{ @attrs[:lat] }, #{ @attrs[:alt] }<\/coordinates>/
        end

        it 'handles extrude properly' do
            @o.extrude = true 
            k = @o.to_kml
            k.should =~ /<extrude>1<\/extrude>/
            @o.extrude = false 
            k = @o.to_kml
            k.should =~ /<extrude>0<\/extrude>/
        end

        it 'provides the correct short form' do
            @o.altitudeMode = :clampToSeaFloor
            @o.extrude = 1
            k = @o.to_kml(0, true)
            k.should_not =~ /<extrude>/
            k.should_not =~ /altitudeMode/
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
        @o.to_kml.should_not =~ /gx:altitudeOffset/
        @o.altitudeOffset = 1
        @o.to_kml.should =~ /gx:altitudeOffset/
        @o.extrude = nil
        @o.to_kml.should_not =~ /extrude/
        @o.extrude = true 
        @o.to_kml.should =~ /extrude/
        @o.tessellate = nil
        @o.to_kml.should_not =~ /tessellate/
        @o.tessellate = true 
        @o.to_kml.should =~ /tessellate/
        @o.drawOrder = nil
        @o.to_kml.should_not =~ /gx:drawOrder/
        @o.drawOrder = true 
        @o.to_kml.should =~ /gx:drawOrder/
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
        @o.to_kml.should_not =~ /gx:altitudeOffset/
        @o.altitudeOffset = 1
        @o.to_kml.should =~ /gx:altitudeOffset/
        @o.extrude = nil
        @o.to_kml.should_not =~ /extrude/
        @o.extrude = true 
        @o.to_kml.should =~ /extrude/
        @o.tessellate = nil
        @o.to_kml.should_not =~ /tessellate/
        @o.tessellate = true 
        @o.to_kml.should =~ /tessellate/
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
        k.should =~ /<Camera/
        k.should =~ /<roll>/
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
        k.should =~ /<LookAt/
        k.should =~ /<range>/
    end
end
