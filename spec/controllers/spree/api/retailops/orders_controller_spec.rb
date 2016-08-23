require 'spec_helper'

describe Spree::Api::Retailops::OrdersController do
  render_views
  before do
    stub_authentication!
  end

  context "as a random user" do
    it "cannot export orders" do
      spree_xhr_post :index
      assert_unauthorized!
    end

    it "cannot mark orders imported" do
      spree_xhr_post :export, ids: []
      assert_unauthorized!
    end
  end

  context "signed in as admin" do
    sign_in_as_admin!

    it "fetch no orders" do
      order = create(:order, retailops_import: 'no')
      spree_xhr_post :index
      expect(json_response).to eq([])
    end

    it "fetch one order" do
      order = create(:order_ready_to_ship, retailops_import: 'yes')
      spree_xhr_post :index
      expect(json_response.size).to eq(1)
      dto = json_response[0]
      expect(dto['total'].to_d).to eq(order.total)
      expect(dto['line_items'].size).to eq(order.line_items.size)
      expect(dto['line_items'][0]['sku']).to eq(order.line_items.first.variant.sku)
    end

    it "can mark orders imported" do
      order = create(:order, retailops_import: 'yes')
      spree_xhr_post :export, ids: [order.id]
      expect(response.status).to eq(200)
      order.reload
      expect(order.retailops_import).to eq('done')
    end
  end
end

describe Spree::Api::Retailops::OrdersController do
  # Synchronize tests
  let(:params) do
    {
      "order_amts" => {
        "shipping_amt" => 4.98,
        "discount_amt" => 0,
        "tax_amt" => 0,
        "direct_tax_amt" => 0
      },
      "rmas" => nil,
      "line_items" => [
        {
          "estimated_extended_cost" => "27.50",
          "apportioned_ship_amt" => 4.98,
          "sku" => "136270",
          "quantity" => "1",
          "estimated_ship_date" => 1458221964,
          "direct_ship_amt" => 0,
          "corr" => "575714",
          "removed" => nil,
          "estimated_cost" => 27.5,
          "estimated_unit_cost" => 27.5,
          "unit_price" => 49.98
        }
      ],
      "options" => {},
      "order_refnum" => "R280725117",
      "order" => {}
    }
  end

  let(:line_items) do
    params["line_items"].map do |line_item_hash|
      create(:line_item, {
        quantity: line_item_hash["quantity"].to_i,
        cost_price: line_item_hash["estimated_unit_cost"].to_d,
        price: line_item_hash["unit_price"].to_d,
        variant: create(:variant, sku: line_item_hash["sku"])
      })
    end
  end

  let(:order) do
    create(:order, number: params["order_refnum"], line_items: line_items)
  end

  let(:user) { create(:admin_user, spree_api_key: "key") }

  let(:mock_handler) do
    Struct.new(:order, :params) do
      def call
        [true, []]
      end
    end
  end

  before do
    order
  end

  describe "#synchronize" do
    it "will call out to default line item processor" do
      expect_any_instance_of(Spree::Retailops::RopLineItemUpdater).to receive(:call).and_return([true, []])
      post :synchronize, params.merge(use_route: :synchronize_retailops_api, token: user.spree_api_key)
      response_data = JSON.parse(response.body)
      expect(response_data["changed"]).to be(true)
    end

    it "will call out custom line item processor if it exists" do
      stub_const("RetailopsLineItemUpdateHandler", mock_handler)
      expect_any_instance_of(RetailopsLineItemUpdateHandler).to receive(:call).and_call_original
      post :synchronize, params.merge(use_route: :synchronize_retailops_api, token: user.spree_api_key)
      response_data = JSON.parse(response.body)
      expect(response_data["changed"]).to be(true)
    end
  end
end
