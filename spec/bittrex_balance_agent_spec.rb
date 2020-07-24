require 'rails_helper'
require 'huginn_agent/spec_helper'

describe Agents::BittrexBalanceAgent do
  before(:each) do
    @valid_options = Agents::BittrexBalanceAgent.new.default_options
    @checker = Agents::BittrexBalanceAgent.new(:name => "BittrexBalanceAgent", :options => @valid_options)
    @checker.user = users(:bob)
    @checker.save!
  end

  pending "add specs here"
end
