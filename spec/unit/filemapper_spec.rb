require 'spec_helper'
require 'puppetx/filemapper'

describe PuppetX::FileMapper do

  before do
    @ramtype  = Puppet::Util::FileType.filetype(:ram)
    @flattype = stub 'Class<FileType<Flat>>'

    Puppet::Util::FileType.stubs(:filetype).with(:flat).returns @flattype
  end

  let(:dummytype) do
    Puppet::Type.newtype(:dummy) do
      newparam(:name, :namevar => true)
      newparam(:fooparam)
      newproperty(:barprop)
    end
  end

  after :each do
    dummytype.provider_hash.clear
  end

  describe 'when included' do
    it 'should initialize the provider as not failed' do
      provider = dummytype.provide(:foo) { include PuppetX::FileMapper }
      provider.failed.should be_false
    end
  end

  describe 'when validating the class' do
    describe "and it doesn't implement self.target_files" do
      subject do
        dummytype.provide(:incomplete) { include PuppetX::FileMapper }
      end

      it { expect { subject.validate_class! }.to raise_error Puppet::DevError, /target_files/ }
    end

    describe "and it doesn't implement self.parse_file" do
      subject do
        dummytype.provide(:incomplete) do
          include PuppetX::FileMapper
          def self.target_files; end
        end
      end

      it { expect { subject.validate_class! }.to raise_error Puppet::DevError, /parse_file/}
    end
  end

  describe 'when reading' do
    describe 'a single file' do

      let(:data) { [{:name => 'yay', :fooparam => :bla, :barprop => 'baz'}] }

      subject do
        dummytype.provide(:single) do
          include PuppetX::FileMapper
          def self.target_files; ['/foo']; end
          def self.parse_file(filename, content)
            [{:name => 'yay', :fooparam => :bla, :barprop => 'baz'}]
          end
        end
      end

      it 'should generate a filetype for that file' do
        @flattype.expects(:new).with('/foo').once.returns @ramtype.new('/foo')
        subject.load_all_providers_from_disk
      end

      it 'should parse each file' do
        stub_file = stub(:read => 'file contents')
        @flattype.stubs(:new).with('/foo').once.returns stub_file
        subject.expects(:parse_file).with('/foo', 'file contents').returns []
        subject.load_all_providers_from_disk
      end

      it 'should return the generated array' do
        @flattype.stubs(:new).with('/foo').once.returns @ramtype.new('/foo')
        subject.load_all_providers_from_disk.should == data
      end
    end

    describe 'multiple files' do
      subject do
        dummytype.provide(:multiple) do
          include PuppetX::FileMapper
          def self.target_files; ['/bar', '/baz']; end
          def self.parse_file(filename, content)
            case filename
            when '/bar' then [{:name => 'yay', :fooparam => :bla, :barprop => 'baz'}]
            when '/baz' then [{:name => 'whee', :fooparam => :ohai, :barprop => 'wat'}]
            end
          end
        end
      end

      it 'should generate a filetype for each file' do
        @flattype.expects(:new).with('/bar').once.returns(stub(:read => 'barbar'))
        @flattype.expects(:new).with('/baz').once.returns(stub(:read => 'bazbaz'))
        subject.load_all_providers_from_disk
      end

      describe 'when parsing' do
        before do
          @flattype.stubs(:new).with('/bar').once.returns(stub(:read => 'barbar'))
          @flattype.stubs(:new).with('/baz').once.returns(stub(:read => 'bazbaz'))
        end

        it 'should parse each file' do
          subject.expects(:parse_file).with('/bar', 'barbar').returns []
          subject.expects(:parse_file).with('/baz', 'bazbaz').returns []
          subject.load_all_providers_from_disk
        end

        it 'should return the generated array' do
          data = subject.load_all_providers_from_disk
          data.should be_include({:name => 'yay', :fooparam => :bla, :barprop => 'baz'})
          data.should be_include({:name => 'whee', :fooparam => :ohai, :barprop => 'wat'})
        end
      end
    end
  end

  describe 'when generating instances' do
    subject do
      dummytype.provide(:multiple) do
        include PuppetX::FileMapper
        attr_reader :property_hash
        def self.target_files; ['/bar', '/baz']; end
        def self.parse_file(filename, content)
          case filename
          when '/bar' then [{:name => 'yay', :fooparam => :bla, :barprop => 'baz'}]
          when '/baz' then [{:name => 'whee', :fooparam => :ohai, :barprop => 'wat'}]
          end
        end
      end
    end

    before do
      @flattype.stubs(:new).with('/bar').once.returns(stub(:read => 'barbar'))
      @flattype.stubs(:new).with('/baz').once.returns(stub(:read => 'bazbaz'))
    end

    let(:yayhash)  {{:name => 'yay', :fooparam => :bla, :barprop => 'baz', :provider => subject.name}}
    let(:wheehash) {{:name => 'whee', :fooparam => :ohai, :barprop => 'wat', :provider => subject.name}}

    it 'should generate a provider instance from hashes' do

      subject.expects(:new).with(yayhash).returns stub()
      subject.expects(:new).with(wheehash).returns stub()
      subject.instances

    end

    it 'should generate a provider instance for each hash' do
      provs = subject.instances
      provs.should have(2).items
      provs.each { |prov| prov.should be_a_kind_of(Puppet::Provider)}
    end

    [
      {:name => 'yay', :fooparam => :bla, :barprop => 'baz'},
      {:name => 'whee', :fooparam => :ohai, :barprop => 'wat'},
    ].each do |values|
      it "should match hash values to provider properties for #{values[:name]}" do
        provs = subject.instances
        prov = provs.find {|prov| prov.name == values[:name]}
        values.each_pair { |property, value| prov.send(property).should == value }
      end
    end
  end

  describe 'when prefetching' do
    subject do
      dummytype.provide(:multiple) do
        include PuppetX::FileMapper
        attr_reader :property_hash
        def self.target_files; ['/bar', '/baz']; end
        def self.parse_file(filename, content)
          case filename
          when '/bar' then [{:name => 'yay', :fooparam => :bla, :barprop => 'baz'}]
          when '/baz' then [{:name => 'whee', :fooparam => :ohai, :barprop => 'wat'}]
          end
        end
      end
    end

    before do
      @yay_params = {:name => 'yay', :fooparam => :bla, :barprop => 'baz'}
      @whee_params = {:name => 'whee', :fooparam => :ohai, :barprop => 'wat'}
      @dead_params = {:name => 'dead', :fooparam => :nofoo, :barprop => 'sadprop'}

      @provider_yay = subject.new(@yay_params.merge({:provider => subject.name}))
      @provider_whee = subject.new(@whee_params.merge({:provider => subject.name}))

      subject.stubs(:instances).returns [@provider_yay, @provider_whee]
    end

    let(:resources) do
      [@yay_params, @whee_params, @dead_params].inject({}) do |h, params|
        h[params[:name]] = dummytype.new(params)
        h
      end
    end

    it "should update resources with existing providers" do
      resources['yay'].expects(:provider=).with(@provider_yay)
      resources['whee'].expects(:provider=).with(@provider_whee)

      subject.prefetch(resources)
    end

    it "should not update resources that don't have providers" do
      resources['dead'].expects(:provider=).never
      subject.prefetch(resources)
    end
  end
end
