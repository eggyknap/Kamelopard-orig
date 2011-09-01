# vim:ts=4:sw=4:et:smartindent:nowrap
$LOAD_PATH << './lib'
require 'kamelopard'
require 'rexml/document'

shared_examples_for 'KMLObject' do
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

    it_should_behave_like 'KMLObject'
    it_should_behave_like 'KML_includes_id'

    it 'descends from the right class' do
        a = @o.kind_of? Geometry
        a.should == true
    end

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

    it 'returns decent KML' do
        @o << [[1,2,3], [2,3,4], [3,4,5]]
        k = @o.to_kml
        k.should =~ /<coordinates>\n.*\n<\/coordinates>/
        k.should =~ /1.0,2.0,3.0/
        k.should =~ /2.0,3.0,4.0/
        k.should =~ /3.0,4.0,5.0/
    end
end
