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

      let(:data) { [{:name => 'yay', :foo => :bla, :bar => 'baz'}] }

      subject do
        dummytype.provide(:single) do
          include PuppetX::FileMapper
          def self.target_files; ['/foo']; end
          def self.parse_file(filename, content)
            [{:name => 'yay', :foo => :bla, :bar => 'baz'}]
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
            when '/bar' then [{:name => 'yay', :foo => :bla, :bar => 'baz'}]
            when '/baz' then [{:name => 'whee', :foo => :ohai, :bar => 'wat'}]
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
          data.should be_include({:name => 'yay', :foo => :bla, :bar => 'baz'})
          data.should be_include({:name => 'whee', :foo => :ohai, :bar => 'wat'})
        end
      end
    end
  end
end
