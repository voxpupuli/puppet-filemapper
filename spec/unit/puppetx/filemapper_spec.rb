require 'spec_helper'
require 'puppetx/filemapper'

describe PuppetX::FileMapper do

  before do
    @ramtype  = Puppet::Util::FileType.filetype(:ram)
    @flattype = stub 'Class<FileType<Flat>>'


    Puppet::Util::FileType.stubs(:filetype).with(:flat).returns @flattype
  end

  after :each do
    dummytype.defaultprovider = nil
  end

  let(:dummytype) do
    Puppet::Type.newtype(:dummy) do
      ensurable
      newparam(:name, :namevar => true)
      newparam(:fooparam)
      newproperty(:barprop)
    end
  end

  let(:single_file_provider) do
    dummytype.provide(:single) do
      include PuppetX::FileMapper
      def self.target_files; ['/foo']; end
      def self.parse_file(filename, content)
        [{:name => 'yay', :fooparam => :bla, :barprop => 'baz'}]
      end
      def select_file; '/foo'; end
      def self.format_file(filename, providers); 'flushback'; end
    end
  end

  let(:multiple_file_provider) do
    dummytype.provide(:multiple, :resource_type => dummytype) do
      include PuppetX::FileMapper
      def self.target_files; ['/bar', '/baz']; end
      def self.parse_file(filename, content)
        case filename
        when '/bar' then [{:name => 'yay', :fooparam => :bla, :barprop => 'baz'}]
        when '/baz' then [{:name => 'whee', :fooparam => :ohai, :barprop => 'wat'}]
        end
      end
      def select_file; '/blor'; end
      def self.format_file(filename, providers); 'multiple flush'; end
    end
  end

  let(:params_yay)  { {:name => 'yay', :fooparam => :bla, :barprop => 'baz'} }
  let(:params_whee) { {:name => 'whee', :fooparam => :ohai, :barprop => 'wat'} }
  let(:params_nope) { {:name => 'dead', :fooparam => :nofoo, :barprop => 'sadprop'} }

  after :each do
    dummytype.provider_hash.clear
  end

  describe 'when included' do
    it 'should initialize the provider as not failed' do
      provider = dummytype.provide(:foo) { include PuppetX::FileMapper }
      provider.should_not be_failed
    end

    describe 'when generating attr_accessors' do
      subject { multiple_file_provider.new(params_yay) }

      describe 'for properties' do
        it { should respond_to :barprop }
        it { should respond_to :barprop= }
        it { should respond_to :ensure }
        it { should respond_to :ensure= }
      end

      describe 'for parameters' do
        it { should_not respond_to :fooparam }
        it { should_not respond_to :fooparam= }
      end
    end
  end

  describe 'when validating the class' do
    describe "and it doesn't implement self.target_files" do
      subject do
        dummytype.provide(:incomplete) { include PuppetX::FileMapper }
      end

      it { expect { subject.validate_class! }.to raise_error Puppet::DevError, /self.target_files/ }
    end

    describe "and it doesn't implement self.parse_file" do
      subject do
        dummytype.provide(:incomplete) do
          include PuppetX::FileMapper
          def self.target_files; end
        end
      end

      it { expect { subject.validate_class! }.to raise_error Puppet::DevError, /self.parse_file/}
    end

    describe "and it doesn't implement #select_file" do
      subject do
        dummytype.provide(:incomplete) do
          include PuppetX::FileMapper
          def self.target_files; end
          def self.parse_file(filename, content); end
          def self.format_file(filename, resources); 'foo'; end
        end
      end

      it { expect { subject.validate_class! }.to raise_error Puppet::DevError, /#select_file/}
    end

    describe "and it doesn't implement self.format_file" do
      subject do
        dummytype.provide(:incomplete) do
          include PuppetX::FileMapper
          def self.target_files; end
          def self.parse_file(filename, content); end
          def select_file; '/foo'; end
        end
      end

      it { expect { subject.validate_class! }.to raise_error Puppet::DevError, /self\.format_file/}
    end
  end

  describe 'when reading' do
    describe 'a single file' do

      subject { single_file_provider }

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
        subject.load_all_providers_from_disk.should == [params_yay]
      end
    end

    describe 'multiple files' do
      subject { multiple_file_provider }

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
          data.should be_include(params_yay)
          data.should be_include(params_whee)
        end
      end
    end

    describe 'validating input' do
      subject { multiple_file_provider }

      before do
        @flattype.stubs(:new).with('/bar').once.returns(stub(:read => 'barbar'))
        @flattype.stubs(:new).with('/baz').once.returns(stub(:read => 'bazbaz'))
      end

      it 'should ensure that retrieved values are in the right format' do
        subject.stubs(:parse_file).with('/bar', 'barbar').returns Hash.new
        subject.stubs(:parse_file).with('/baz', 'bazbaz').returns Hash.new

        expect { subject.load_all_providers_from_disk }.to raise_error Puppet::DevError, /expected.*to return an Array, got a Hash/
      end
    end
  end

  describe 'when generating instances' do
    subject { multiple_file_provider }

    before do
      @flattype.stubs(:new).with('/bar').once.returns(stub(:read => 'barbar'))
      @flattype.stubs(:new).with('/baz').once.returns(stub(:read => 'bazbaz'))
    end

    it 'should generate a provider instance from hashes' do

      params_yay.merge!({:provider => subject.name})
      params_whee.merge!({:provider => subject.name})

      subject.expects(:new).with(params_yay.merge({:ensure => :present})).returns stub()
      subject.expects(:new).with(params_whee.merge({:ensure => :present})).returns stub()
      subject.instances

    end

    it 'should generate a provider instance for each hash' do
      provs = subject.instances
      provs.should have(2).items
      provs.each { |prov| prov.should be_a_kind_of(Puppet::Provider)}
    end

    [
      {:name => 'yay', :barprop => 'baz'},
      {:name => 'whee', :barprop => 'wat'},
    ].each do |values|
      it "should match hash values to provider properties for #{values[:name]}" do
        provs = subject.instances
        prov = provs.find {|prov| prov.name == values[:name]}
        values.each_pair { |property, value| prov.send(property).should == value }
      end
    end
  end

  describe 'when prefetching' do
    subject { multiple_file_provider }

    let(:provider_yay) { subject.new(params_yay.merge({:provider => subject.name})) }
    let(:provider_whee) { subject.new(params_whee.merge({:provider => subject.name})) }

    before do
      subject.stubs(:instances).returns [provider_yay, provider_whee]
    end

    let(:resources) do
      [params_yay, params_whee, params_nope].inject({}) do |h, params|
        h[params[:name]] = dummytype.new(params)
        h
      end
    end

    it "should update resources with existing providers" do
      resources['yay'].expects(:provider=).with(provider_yay)
      resources['whee'].expects(:provider=).with(provider_whee)

      subject.prefetch(resources)
    end

    it "should not update resources that don't have providers" do
      resources['dead'].expects(:provider=).never
      subject.prefetch(resources)
    end
  end

  describe 'on resource state change' do
    subject { multiple_file_provider }

    before do
      dummytype.defaultprovider = subject
      subject.any_instance.stubs(:resource_type).returns dummytype
    end

    describe 'from absent to present' do
      let(:resource) { dummytype.new(:name => 'boom', :barprop => 'bang') }
      it 'should mark the related file as dirty' do
        subject.mapped_files['/blor'][:dirty].should be_false
        resource.property(:ensure).sync
        subject.mapped_files['/blor'][:dirty].should be_true
      end
    end

    describe 'from present to absent' do
      it 'should mark the related file as dirty' do
        resource = dummytype.new(:name => 'boom', :barprop => 'bang', :ensure => :absent)
        subject.mapped_files['/blor'][:dirty].should be_false
        resource.property(:ensure).sync
        subject.mapped_files['/blor'][:dirty].should be_true
      end
    end

    describe 'on a property' do
      let(:resource) { resource = dummytype.new(params_yay) }

      before do
        prov = subject.new(params_yay.merge({:ensure => :present}))
        subject.stubs(:instances).returns [prov]
        subject.prefetch({params_yay[:name] => resource})
      end

      it 'should mark the related file as dirty' do
        subject.mapped_files['/blor'][:dirty].should be_false
        resource.property(:barprop).value = 'new value'
        resource.property(:barprop).sync
        subject.mapped_files['/blor'][:dirty].should be_true
      end
    end

    describe 'on a parameter' do
      let(:resource) { resource = dummytype.new(params_yay) }

      before do
        prov = subject.new(params_yay.merge({:ensure => :present}))
        subject.stubs(:instances).returns [prov]
        subject.prefetch({params_yay[:name] => resource})
      end

      it 'should not mark the related file as dirty' do
        subject.mapped_files['/blor'][:dirty].should be_false
        resource.parameter(:fooparam).value = 'new value'
        resource.flush
        subject.mapped_files['/blor'][:dirty].should be_false
      end
    end
  end

  describe 'when determining whether to flush' do
    subject { multiple_file_provider }

    before do
      dummytype.defaultprovider = subject
      subject.any_instance.stubs(:resource_type).returns dummytype
    end

    let(:resource) { resource = dummytype.new(params_yay) }

    it 'should refuse to flush if the provider is in a failed state' do
      subject.dirty_file!('/blor')
      subject.failed!
      subject.expects(:collect_resources_for_provider).never
      resource.flush
    end

    it 'should use the provider instance method `select_file` to locate the destination file' do
      resource.provider.expects(:select_file).returns '/blor'
      resource.property(:barprop).value = 'zoom'
      resource.property(:barprop).sync
    end

    it 'should trigger the class dirty_file! method' do
      subject.expects(:dirty_file!).with('/blor')
      resource.property(:barprop).value = 'zoom'
      resource.property(:barprop).sync
    end

    it 'should forward provider#flush to the class' do
      subject.expects(:flush_file).with('/blor')
      resource.flush
    end

    describe 'and performing the flush' do

      let(:newtype) { @ramtype.new('/blor') }
      before { newtype.stubs(:backup) }

      it 'should generate filetypes for new files' do
        subject.dirty_file!('/blor')
        @flattype.expects(:new).with('/blor').returns newtype
        resource.flush
      end

      it 'should use existing filetypes for existing files' do
        stub_filetype = stub()
        stub_filetype.expects(:backup)
        stub_filetype.expects(:write)
        subject.dirty_file!('/blor')
        subject.mapped_files['/blor'][:filetype] = stub_filetype
        resource.flush
      end

      it 'should trigger a flush on dirty files' do
        subject.dirty_file!('/blor')
        subject.expects(:perform_write).with('/blor', 'multiple flush')
        resource.flush
      end

      it 'should not flush clean files' do
        subject.expects(:perform_write).never
        resource.flush
      end
    end

    describe 'validating the file contents to flush' do
      before do
        subject.stubs(:format_file).returns %w{invalid data}
        subject.dirty_file!('/blor')
      end

      it 'should raise an error if given an invalid value for file contents' do
        subject.expects(:perform_write).with('/blor', %w{invalid data}).never
        expect { subject.flush_file('/blor') }.to raise_error Puppet::DevError, /expected .* to return a String, got a Array/
      end
    end
  end

  describe 'when formatting resources for flushing' do
    let(:provider_class) { multiple_file_provider }

    let(:new_resource) { dummytype.new(params_yay) }

    let(:current_provider) { provider_class.new(params_whee) }
    let(:current_resource) { dummytype.new(params_whee) }

    let(:remove_provider) { provider_class.new(params_nope) }
    let(:remove_resource) { dummytype.new(params_nope.merge({:ensure => :absent})) }

    let(:unmanaged_provider) { provider_class.new(:name => 'ignoreme', :fooparam => 'zoom', :barprop => 'squid', :ensure => :present) }

    let(:provider_stubs) { [current_provider, remove_provider, unmanaged_provider] }
    let(:resource_stubs) { [new_resource, current_resource, remove_resource] }

    before do
      dummytype.defaultprovider = provider_class
      provider_class.any_instance.stubs(:resource_type).returns dummytype

      provider_class.stubs(:instances).returns provider_stubs
      provider_class.prefetch(resource_stubs.inject({}) { |h, r| h[r.name] = r; h})

      # Pretend that we're the resource harness and apply the ensure param
      resource_stubs.each { |r| r.property(:ensure).sync }
    end

    it 'should collect all resources for a given file' do
      provider_class.expects(:collect_providers_for_file).with('/blor').returns []
      provider_class.stubs(:perform_write)
      provider_class.flush_file('/blor')
    end

    describe 'and selecting' do
      subject { multiple_file_provider.collect_providers_for_file('/blor').map(&:name) }

      describe 'present resources' do
        it { should be_include 'yay' }
        it { should be_include 'whee' }
        it { should be_include 'ignoreme' }
      end

      describe 'absent resources' do
        it { should_not be_include 'nope' }
      end
    end
  end
end
