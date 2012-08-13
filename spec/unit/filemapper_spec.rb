require 'puppet'
require 'puppetx/filemapper'

describe PuppetX::FileMapper do

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

      it '' do
        expect { subject.validate_class! }.to raise_error
      end
    end

  end

end
