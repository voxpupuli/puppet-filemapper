require 'puppet'
require 'puppetx/filemapper'

describe PuppetX::FileMapper do

  before do
    @ramtype  = Puppet::Util::FileType.filetype(:ram)
    @flattype = Puppet::Util::FileType.filetype(:flat)

    puts Puppet::Util::FileType.stub(:filetype).with(:flat)
    puts Puppet::Util::FileType.stub(:filetype).with(:flat).and_return @ramtype
  end

  let(:dummytype) do
    Puppet::Type.newtype(:dummy) do
      newparam(:name, :namevar => true)
      newparam(:foo)
      newproperty(:bar)
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
      subject do
        dummytype.provide(:incomplete) do
          include PuppetX::FileMapper
          def self.target_files; ['/foo']; end
          def self.parse_file(filename, content)
            [{:name => 'yay', :foo => :bla, :bar => 'baz'}]
          end
        end
      end

      it 'should generate a filetype for each file' do
        puts @flattype.methods.sort
        @flattype.stub(:new).with('/foo').once.and_return @ramtype.new('/foo')
        subject.load_all_providers_from_disk
      end
    end
  end
end
