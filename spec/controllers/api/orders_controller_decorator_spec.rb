# model on https://github.com/solidusio/solidus_legacy_return_authorizations/blob/b2b8eee6dde9c8a2cf07ff083673128d2f58a0af/spec/controllers/spree/api/legacy_return_authorizations_controller_spec.rb
require 'spec_helper'

module Spree
  describe Spree::Api::OrdersController do
    render_views

    before do
      stub_authentication!
    end

    context "as the order owner" do
      let(:order) { create(:order) }
      let(:current_api_user) { order.user }

      it "cannot set import state" do
        spree_post :retailops_importable, id: order.to_param, importable: 'done', format: :json
        assert_unauthorized!
      end
    end

    context "as an admin" do
      before { current_api_user.stub has_spree_role?: true }

      it "can set import state if not done" do
        order = create(:order)
        order.retailops_import = 'yes'
        order.save
        spree_post :retailops_importable, id: order.to_param, importable: 'no', format: :json
        response.status.should == 200
        expect(order.reload.retailops_import).to eq('no')
      end

      it "cannot set import state if done" do
        order = create(:order)
        order.retailops_import = 'done'
        order.save
        spree_post :retailops_importable, id: order.to_param, importable: 'no', format: :json
        response.status.should == 200
        expect(order.reload.retailops_import).to eq('done')
      end
    end
  end
end
