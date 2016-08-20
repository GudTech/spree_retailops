require 'spec_helper'

module Spree
  describe Spree::Api::Retailops::InventoryController do
    render_views
    before do
      stub_authentication!
    end

    let(:the_variant) do
      create(:variant, sku: '123')
    end

    context "as a random user" do
      it "cannot import inventory" do
        spree_xhr_post :inventory_push, inventory_data: []
        assert_unauthorized!
      end
    end

    context "as an admin" do
      sign_in_as_admin!

      it "can do a no-op empty import" do
        spree_xhr_post :inventory_push, inventory_data: []
        response.status.should == 200
      end

      it "can update inventory" do
        spree_xhr_post :inventory_push, inventory_data: [{ 'sku' => the_variant.sku, 'stock' => { 'a_loc' => 10, 'b_loc' => 1 } }]
        response.status.should == 200

        the_variant.reload
        the_variant.stock_items.sum(:count_on_hand).should == 11
        the_variant.stock_items.select{ |si| si.stock_location.name == 'a_loc' }.map(&:count_on_hand).sum.should == 10
      end
    end
  end
end
