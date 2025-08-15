# frozen_string_literal: true

require 'spec_helper'
require 'puppetx/filemapper'

describe PuppetX::FileMapper do
  before do
    @ramtype  = Puppet::Util::FileType.filetype(:ram)
    @flattype = double('Class<FileType<Flat>>')
    @crontype = double('Class<FileType<Crontab>>')

    allow(Puppet::Util::FileType).to receive(:filetype).with(:flat).and_return(@flattype)
    allow(Puppet::Util::FileType).to receive(:filetype).with(:crontab).and_return(@crontype)
  end

  after do
    dummytype.defaultprovider = nil
    dummytype.provider_hash.clear
  end

  let(:dummytype) do
    Puppet::Type.newtype(:dummy) do
      ensurable
      newparam(:name, namevar: true)
      newparam(:dummy_param)
      newproperty(:dummy_property)
    end
  end

  let(:single_file_provider) do
    dummytype.provide(:single) do
      include PuppetX::FileMapper
      def self.target_files
        ['/single/file/provider']
      end

      def self.parse_file(_filename, _content)
        [{ name: 'yay', dummy_param: :bla, dummy_property: 'baz' }]
      end

      def select_file
        '/single/file/provider'
      end

      def self.format_file(_filename, _providers)
        'flushback'
      end
    end
  end

  let(:multiple_file_provider) do
    dummytype.provide(:multiple, resource_type: dummytype) do
      include PuppetX::FileMapper
      def self.target_files
        ['/multiple/file/provider-one', '/multiple/file/provider-two']
      end

      def self.parse_file(filename, _content)
        case filename
        when '/multiple/file/provider-one' then [{ name: 'yay', dummy_param: :bla, dummy_property: 'baz' }]
        when '/multiple/file/provider-two' then [{ name: 'whee', dummy_param: :ohai, dummy_property: 'wat' }]
        end
      end

      def select_file
        '/multiple/file/provider-flush'
      end

      def self.format_file(_filename, _providers)
        'multiple flush content'
      end
    end
  end

  let(:params_yay)  { { name: 'yay', dummy_param: :bla, dummy_property: 'baz' } }
  let(:params_whee) { { name: 'whee', dummy_param: :ohai, dummy_property: 'wat' } }
  let(:params_nope) { { name: 'dead', dummy_param: :nofoo, dummy_property: 'sadprop' } }

  describe 'when included' do
    describe 'after initializing attributes' do
      subject { dummytype.provide(:foo) { include PuppetX::FileMapper } }

      it do
        expect(subject.mapped_files).to be_empty
        expect(subject.unlink_empty_files).to be(false)
        expect(subject.filetype).to eq(:flat)
        expect(subject).not_to be_failed
      end
    end

    describe 'when generating attr_accessors' do
      subject { multiple_file_provider.new(params_yay) }

      describe 'for properties' do
        it do
          expect(subject).to respond_to(:dummy_property)
          expect(subject).to respond_to(:dummy_property=)
          expect(subject).to respond_to(:ensure)
          expect(subject).to respond_to(:ensure=)
        end
      end

      describe 'for parameters' do
        it do
          expect(subject).not_to respond_to(:dummy_param)
          expect(subject).not_to respond_to(:dummy_param=)
        end
      end
    end
  end

  describe 'when validating the class' do
    describe "and it doesn't implement self.target_files" do
      subject do
        dummytype.provide(:incomplete) { include PuppetX::FileMapper }
      end

      it do
        expect { subject.validate_class! }.to raise_error(Puppet::DevError, %r{self.target_files})
      end
    end

    describe "and it doesn't implement self.parse_file" do
      subject do
        dummytype.provide(:incomplete) do
          include PuppetX::FileMapper
          def self.target_files; end
        end
      end

      it { expect { subject.validate_class! }.to raise_error(Puppet::DevError, %r{self.parse_file}) }
    end

    describe "and it doesn't implement #select_file" do
      subject do
        dummytype.provide(:incomplete) do
          include PuppetX::FileMapper
          def self.target_files; end

          def self.parse_file(_filename, _content); end

          def self.format_file(_filename, _resources)
            'foo'
          end
        end
      end

      it { expect { subject.validate_class! }.to raise_error(Puppet::DevError, %r{#select_file}) }
    end

    describe "and it doesn't implement self.format_file" do
      subject do
        dummytype.provide(:incomplete) do
          include PuppetX::FileMapper
          def self.target_files; end

          def self.parse_file(_filename, _content); end

          def select_file
            '/single/file/provider'
          end
        end
      end

      it { expect { subject.validate_class! }.to raise_error(Puppet::DevError, %r{self\.format_file}) }
    end
  end

  describe 'when reading' do
    describe 'a single file' do
      subject { single_file_provider }

      it 'generates a filetype for that file' do
        expect(@flattype).to receive(:new).with('/single/file/provider').once.and_return(@ramtype.new('/single/file/provider'))
        subject.load_all_providers_from_disk
      end

      it 'parses each file' do
        stub_file = double(read: 'file contents', path: '/single/file/provider')
        allow(@flattype).to receive(:new).with('/single/file/provider').once.and_return(stub_file)
        expect(subject).to receive(:parse_file).with('/single/file/provider', 'file contents').and_return([])
        subject.load_all_providers_from_disk
      end

      it 'returns the generated array' do
        allow(@flattype).to receive(:new).with('/single/file/provider').once.and_return(@ramtype.new('/single/file/provider'))
        expect(subject.load_all_providers_from_disk).to eq([params_yay])
      end
    end

    describe 'multiple files' do
      subject { multiple_file_provider }

      let(:provider_one_stub) { double(read: 'barbar', path: '/multiple/file/provider-one') }
      let(:provider_two_stub) { double(read: 'bazbaz', path: '/multiple/file/provider-two') }

      before do
        expect(@flattype).to receive(:new).with('/multiple/file/provider-one').once.and_return(provider_one_stub)
        expect(@flattype).to receive(:new).with('/multiple/file/provider-two').once.and_return(provider_two_stub)
      end

      it 'generates a filetype for each file' do
        subject.load_all_providers_from_disk
      end

      describe 'when parsing' do
        it 'parses each file' do
          expect(subject).to receive(:parse_file).with('/multiple/file/provider-one', 'barbar').and_return([])
          expect(subject).to receive(:parse_file).with('/multiple/file/provider-two', 'bazbaz').and_return([])
          subject.load_all_providers_from_disk
        end

        it 'returns the generated array' do
          data = subject.load_all_providers_from_disk
          expect(data).to include(params_yay)
          expect(data).to include(params_whee)
        end
      end
    end

    describe 'validating input' do
      subject { multiple_file_provider }

      let(:provider_one_stub) { double(read: 'barbar', path: '/multiple/file/provider-one') }
      let(:provider_two_stub) { double(read: 'bazbaz', path: '/multiple/file/provider-two') }

      before do
        expect(@flattype).to receive(:new).with('/multiple/file/provider-one').once.and_return(provider_one_stub)
        expect(@flattype).to receive(:new).with('/multiple/file/provider-two').once.and_return(provider_two_stub)
      end

      it 'ensures that retrieved values are in the right format' do
        expect(subject).to receive(:parse_file).with('/multiple/file/provider-one', 'barbar').and_return({})
        allow(subject).to receive(:parse_file).with('/multiple/file/provider-two', 'bazbaz').and_return({})

        expect { subject.load_all_providers_from_disk }.to raise_error(Puppet::DevError, %r{expected.*to return an Array, got a Hash})
      end
    end
  end

  describe 'when generating instances' do
    subject { multiple_file_provider }

    let(:provider_one_stub) { double(read: 'barbar', path: '/multiple/file/provider-one') }
    let(:provider_two_stub) { double(read: 'bazbaz', path: '/multiple/file/provider-two') }

    before do
      expect(@flattype).to receive(:new).with('/multiple/file/provider-one').once.and_return(provider_one_stub)
      expect(@flattype).to receive(:new).with('/multiple/file/provider-two').once.and_return(provider_two_stub)
    end

    it 'generates a provider instance from hashes' do
      params_yay[:provider] = subject.name
      params_whee[:provider] = subject.name

      expect(subject).to receive(:new).with(params_yay.merge(ensure: :present)).and_return(double)
      expect(subject).to receive(:new).with(params_whee.merge(ensure: :present)).and_return(double)
      subject.instances
    end

    it 'generates a provider instance for each hash' do
      provs = subject.instances
      expect(provs.size).to eq(2)
      expect(provs).to all(be_a(Puppet::Provider))
    end

    [
      { name: 'yay', dummy_property: 'baz' },
      { name: 'whee', dummy_property: 'wat' }
    ].each do |values|
      it "matches hash values to provider properties for #{values[:name]}" do
        provs = subject.instances
        prov = provs.find { |foundprov| foundprov.name == values[:name] }
        values.each_pair { |property, value| expect(prov.send(property)).to eq(value) }
      end
    end
  end

  describe 'when prefetching' do
    subject { multiple_file_provider }

    let(:provider_yay) { subject.new(params_yay.merge(provider: subject.name)) }
    let(:provider_whee) { subject.new(params_whee.merge(provider: subject.name)) }

    before do
      allow(subject).to receive(:instances).and_return([provider_yay, provider_whee])
    end

    let(:resources) do # rubocop:disable RSpec/ScatteredLet
      [params_yay, params_whee, params_nope].each_with_object({}) do |params, h|
        h[params[:name]] = dummytype.new(params)
      end
    end

    it 'updates resources with existing providers' do
      expect(resources['yay']).to receive(:provider=).with(provider_yay)
      expect(resources['whee']).to receive(:provider=).with(provider_whee)

      subject.prefetch(resources)
    end

    it "does not update resources that don't have providers" do
      expect(resources['dead']).not_to receive(:provider=)
      subject.prefetch(resources)
    end
  end

  describe 'on resource state change' do
    subject { multiple_file_provider }

    before do
      dummytype.defaultprovider = subject
      allow_any_instance_of(subject).to receive(:resource_type).and_return(dummytype)
      subject.mapped_files['/multiple/file/provider-flush'][:dirty] = false
    end

    describe 'from absent to present' do
      let(:resource) { dummytype.new(name: 'boom', dummy_property: 'bang') }

      it 'marks the related file as dirty' do
        expect(subject.mapped_files['/multiple/file/provider-flush'][:dirty]).to be(false)
        resource.property(:ensure).sync
        expect(subject.mapped_files['/multiple/file/provider-flush'][:dirty]).to be(true)
      end
    end

    describe 'from present to absent' do
      it 'marks the related file as dirty' do
        resource = dummytype.new(name: 'boom', dummy_property: 'bang', ensure: :absent)
        expect(subject.mapped_files['/multiple/file/provider-flush'][:dirty]).to be(false)
        resource.property(:ensure).sync
        expect(subject.mapped_files['/multiple/file/provider-flush'][:dirty]).to be(true)
      end
    end

    describe 'on a property' do
      let(:resource) { dummytype.new(params_yay) }

      before do
        prov = subject.new(params_yay.merge(ensure: :present))
        allow(subject).to receive(:instances).and_return([prov])
        subject.prefetch(params_yay[:name] => resource)
      end

      it 'marks the related file as dirty' do
        expect(subject.mapped_files['/multiple/file/provider-flush'][:dirty]).to be(false)
        resource.property(:dummy_property).value = 'new value'
        resource.property(:dummy_property).sync
        expect(subject.mapped_files['/multiple/file/provider-flush'][:dirty]).to be(true)
      end
    end

    describe 'on a parameter' do
      let(:resource) { dummytype.new(params_yay) }

      before do
        prov = subject.new(params_yay.merge(ensure: :present))
        allow(subject).to receive(:instances).and_return([prov])
        subject.prefetch(params_yay[:name] => resource)
      end

      it 'does not mark the related file as dirty' do
        expect(subject.mapped_files['/multiple/file/provider-flush'][:dirty]).to be(false)
        resource.parameter(:dummy_param).value = 'new value'
        resource.flush
        expect(subject.mapped_files['/multiple/file/provider-flush'][:dirty]).to be(false)
      end
    end
  end

  describe 'when determining whether to flush' do
    subject { multiple_file_provider }

    before do
      dummytype.defaultprovider = subject
      allow_any_instance_of(subject).to receive(:resource_type).and_return(dummytype)
    end

    let(:resource) { dummytype.new(params_yay) }

    it 'refuses to flush if the provider is in a failed state' do
      subject.dirty_file!('/multiple/file/provider-flush')
      subject.failed!
      expect(subject).not_to receive(:collect_resources_for_provider)
      resource.flush
    end

    it 'uses the provider instance method `select_file` to locate the destination file' do
      expect(resource.provider).to receive(:select_file).and_return('/multiple/file/provider-flush')
      resource.property(:dummy_property).value = 'zoom'
      resource.property(:dummy_property).sync
    end

    it 'triggers the class dirty_file! method' do
      expect(subject).to receive(:dirty_file!).with('/multiple/file/provider-flush')
      resource.property(:dummy_property).value = 'zoom'
      resource.property(:dummy_property).sync
    end
  end

  describe 'when flushing' do
    subject { multiple_file_provider }

    let(:newtype) { @ramtype.new('/multiple/file/provider-flush') }
    let(:resource) { dummytype.new(params_yay) }

    before { allow(newtype).to receive(:backup) }

    it 'forwards provider#flush to the class' do
      expect(subject).to receive(:flush_file).with('/multiple/file/provider-flush')
      resource.flush
    end

    it 'generates filetypes for new files' do
      subject.dirty_file!('/multiple/file/provider-flush')
      expect(@flattype).to receive(:new).with('/multiple/file/provider-flush').and_return(newtype)
      resource.flush
    end

    it 'uses existing filetypes for existing files' do
      stub_filetype = double
      expect(stub_filetype).to receive(:backup)
      expect(stub_filetype).to receive(:write)
      subject.dirty_file!('/multiple/file/provider-flush')
      subject.mapped_files['/multiple/file/provider-flush'][:filetype] = stub_filetype
      resource.flush
    end

    it 'triggers a flush on dirty files' do
      subject.dirty_file!('/multiple/file/provider-flush')
      expect(subject).to receive(:perform_write).with('/multiple/file/provider-flush', 'multiple flush content')
      resource.flush
    end

    it 'does not flush clean files' do
      expect(subject).not_to receive(:perform_write)
      resource.flush
    end
  end

  describe 'validating the file contents to flush' do
    subject { multiple_file_provider }

    before do
      allow(subject).to receive(:format_file).and_return(%w[definitely not of class String])
      subject.dirty_file!('/multiple/file/provider-flush')
    end

    it 'raises an error if given an invalid value for file contents' do
      expect(subject).not_to receive(:perform_write).with('/multiple/file/provider-flush', %w[invalid data])
      expect { subject.flush_file('/multiple/file/provider-flush') }.to raise_error(Puppet::DevError, %r{expected .* to return a String, got a Array})
    end
  end

  describe 'when unlinking empty files' do
    subject { multiple_file_provider }

    let(:newtype) { @ramtype.new('/multiple/file/provider-flush') }

    before do
      subject.unlink_empty_files = true
      allow(newtype).to receive(:backup)
      allow(File).to receive(:unlink)
    end

    describe 'with empty file contents' do
      before do
        subject.dirty_file!('/multiple/file/provider-flush')
        allow(@flattype).to receive(:new).with('/multiple/file/provider-flush').and_return(newtype)
        allow(File).to receive(:exist?).with('/multiple/file/provider-flush').and_return(true)

        allow(subject).to receive(:format_file).and_return('')
      end

      it 'backs up the file' do
        expect(newtype).to receive(:backup)
        subject.flush_file('/multiple/file/provider-flush')
      end

      it 'removes the file' do
        expect(File).to receive(:unlink).with('/multiple/file/provider-flush')
        subject.flush_file('/multiple/file/provider-flush')
      end

      it 'does not write to the file' do
        expect(subject).not_to receive(:perform_write).with('/multiple/file/provider-flush', '')
        subject.flush_file('/multiple/file/provider-flush')
      end
    end

    describe 'with empty file contents and no destination file' do
      before do
        subject.dirty_file!('/multiple/file/provider-flush')
        allow(@flattype).to receive(:new).with('/multiple/file/provider-flush').and_return(newtype)
        allow(File).to receive(:exist?).with('/multiple/file/provider-flush').and_return(false)

        allow(subject).to receive(:format_file).and_return('')
      end

      it 'does not try to remove the file' do
        expect(File).to receive(:exist?).with('/multiple/file/provider-flush').and_return(false)
        expect(File).not_to receive(:unlink)
        subject.flush_file('/multiple/file/provider-flush')
      end

      it 'does not try to back up the file' do
        expect(newtype).not_to receive(:backup)
        subject.flush_file('/multiple/file/provider-flush')
      end
    end

    describe 'with a non-empty file' do
      before do
        subject.dirty_file!('/multiple/file/provider-flush')
        allow(@flattype).to receive(:new).with('/multiple/file/provider-flush').and_return(newtype)
        allow(File).to receive(:exist?).with('/multiple/file/provider-flush').and_return(true)

        allow(subject).to receive(:format_file).and_return('not empty')
      end

      it 'does not remove the file' do
        expect(File).not_to receive(:unlink)
        subject.flush_file('/multiple/file/provider-flush')
      end
    end
  end

  describe 'when using an alternate filetype' do
    subject { multiple_file_provider }

    before do
      subject.filetype = :crontab
    end

    it 'assigns that filetype to loaded files' do
      expect(@crontype).to receive(:new).with('/multiple/file/provider-one').once.and_return(double(read: 'barbar', path: '/multiple/file/provider-one'))
      expect(@crontype).to receive(:new).with('/multiple/file/provider-two').once.and_return(double(read: 'bazbaz', path: '/multiple/file/provider-two'))

      subject.load_all_providers_from_disk
    end

    describe 'that does not implement backup' do
      let(:resource) { dummytype.new(params_yay) }
      let(:stub_filetype) { double }

      before do
        subject.mapped_files['/multiple/file/provider-flush'][:filetype] = stub_filetype
        subject.dirty_file!('/multiple/file/provider-flush')

        allow(stub_filetype).to receive(:respond_to?).with(:backup).and_return(false)
        expect(stub_filetype).not_to receive(:backup)
      end

      it 'does not call backup when writing files' do
        allow(stub_filetype).to receive(:write)

        resource.flush
      end

      it 'does not call backup when unlinking files' do
        subject.unlink_empty_files = true
        allow(subject).to receive(:format_file).and_return('')
        allow(File).to receive(:exist?).with('/multiple/file/provider-flush').and_return(true)
        allow(File).to receive(:unlink)

        resource.flush
      end
    end
  end

  describe 'flush hooks' do
    subject { multiple_file_provider }

    before do
      subject.dirty_file!('/multiple/file/provider-flush')
    end

    let(:newtype) { @ramtype.new('/multiple/file/provider-flush') }

    it 'is called in order' do
      allow(subject).to receive(:respond_to?).with(:pre_flush_hook).and_return(true)
      allow(subject).to receive(:respond_to?).with(:post_flush_hook).and_return(true)
      expect(subject).to receive(:pre_flush_hook).with('/multiple/file/provider-flush').ordered
      expect(subject).to receive(:perform_write).with('/multiple/file/provider-flush', 'multiple flush content').ordered
      expect(subject).to receive(:post_flush_hook).with('/multiple/file/provider-flush').ordered

      subject.flush_file '/multiple/file/provider-flush'
    end

    it 'calls post_flush_hook even if an exception is raised' do
      allow(subject).to receive(:respond_to?).with(:pre_flush_hook).and_return(false)
      allow(subject).to receive(:respond_to?).with(:post_flush_hook).and_return(true)

      allow(subject).to receive(:perform_write).with('/multiple/file/provider-flush', 'multiple flush content').and_raise(RuntimeError)
      expect(subject).to receive(:post_flush_hook)

      expect { subject.flush_file '/multiple/file/provider-flush' }.to raise_error(RuntimeError)
    end
  end

  describe 'when formatting resources for flushing' do
    let(:provider_class) { multiple_file_provider }

    let(:new_resource) { dummytype.new(params_yay) }

    let(:current_provider) { provider_class.new(params_whee) }
    let(:current_resource) { dummytype.new(params_whee) }

    let(:remove_provider) { provider_class.new(params_nope) }
    let(:remove_resource) { dummytype.new(params_nope.merge(ensure: :absent)) }

    let(:unmanaged_provider) { provider_class.new(name: 'unmanaged_resource', dummy_param: 'zoom', dummy_property: 'squid', ensure: :present) }

    let(:provider_stubs) { [current_provider, remove_provider, unmanaged_provider] }
    let(:resource_stubs) { [new_resource, current_resource, remove_resource] }

    before do
      dummytype.defaultprovider = provider_class
      allow_any_instance_of(provider_class).to receive(:resource_type).and_return(dummytype)

      allow(provider_class).to receive(:instances).and_return(provider_stubs)
      provider_class.prefetch(resource_stubs.each_with_object({}) { |r, h| h[r.name] = r })

      # Pretend that we're the resource harness and apply the ensure param
      resource_stubs.each { |r| r.property(:ensure).sync }
    end

    it 'collects all resources for a given file' do
      expect(provider_class).to receive(:collect_providers_for_file).with('/multiple/file/provider-flush').and_return([])
      allow(provider_class).to receive(:perform_write)
      provider_class.flush_file('/multiple/file/provider-flush')
    end

    describe 'and selecting' do
      subject { multiple_file_provider.collect_providers_for_file('/multiple/file/provider-flush').map(&:name) }

      describe 'present resources' do
        it do
          expect(subject).to include('yay')
          expect(subject).to include('whee')
          expect(subject).to include('unmanaged_resource')
        end
      end

      describe 'absent resources' do
        it do
          expect(subject).not_to include('nope')
        end
      end
    end
  end
end
