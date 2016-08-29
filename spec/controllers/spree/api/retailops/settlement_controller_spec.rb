require 'spec_helper'

describe Spree::Api::Retailops::SettlementController do
  render_views
  before do
    stub_authentication!
  end

  context "as a random user" do
    it "cannot mark orders as shipped" do
      spree_xhr_post :add_packages
      assert_unauthorized!
    end

    it "cannot mark orders as completely shipped" do
      spree_xhr_post :mark_complete
      assert_unauthorized!
    end

    it "cannot issue order refunds" do
      spree_xhr_post :add_refund
      assert_unauthorized!
    end

    it "cannot perform payment operations" do
      spree_xhr_post :payment_command
      assert_unauthorized!
    end

    it "cannot cancel orders" do
      spree_xhr_post :cancel
      assert_unauthorized!
    end
  end

  # specific add_packages tests
  let(:ap_test_order) do
    o = create(:order_ready_to_ship, line_items_count: 2)
    o.shipments.first.inventory_units.each{ |iu| iu.order_id = o.id; iu.save! } # possibly a bug in the factory
    o
  end

  let(:ap_package_dto) do
    {
      "options"      => {},
      "order_refnum" => ap_test_order.number,
      "packages"     => [
        {
          "contents" => [
            {
              "id"       => ap_test_order.line_items.second.id,
              "quantity" => 1
            }
          ],
          "date"     => "2016-08-27T00:22:57Z",
          "from"     => "a location",
          "id"       => "584498",
          "shipcode" => "FedEx Ground",
          "tracking" => "846085121745341"
        }
      ]
    }
  end

  context "signed in as admin" do
    sign_in_as_admin!

    it "can mark packages shipped" do
      spree_xhr_post :add_packages, ap_package_dto
      expect(response.status).to eq(200)

      o = ap_test_order.reload
      expect(o.shipments.shipped.count).to eq(1)
      expect(o.shipments.ready.count).to eq(1)
      s = o.shipments.ready.first
      expect(s.line_items.count).to eq(1)
      expect(s.line_items.first).to eq(o.line_items.first)
      s = o.shipments.shipped.first
      expect(s.line_items.count).to eq(1)
      expect(s.line_items.first).to eq(o.line_items.second)

      expect(s.created_at).to eq(Time.parse('2016-08-27T00:22:57Z'))
      expect(s.shipping_method.name).to eq('FedEx Ground')
      expect(s.tracking).to eq('846085121745341')
      expect(s.number).to eq('P584498')
      expect(s.stock_location.name).to eq('a location')
    end

    it "can mark packages shipped idempotently" do
      2.times do
        spree_xhr_post :add_packages, ap_package_dto
        expect(response.status).to eq(200)
      end

      o = ap_test_order.reload
      expect(o.shipments.shipped.count).to eq(1)
      expect(o.shipments.ready.count).to eq(1)
    end

    it "can call custom #retailops_set_tracking" do
      expect_any_instance_of(Spree::Shipment).to receive(:retailops_set_tracking) do |ship, pkg|
        expect(pkg['from']).to eq('a location')
        ship.tracking = '1234'
        ship.shipping_rates.delete_all
        ship.cost = 0.to_d
        mm = Spree::ShippingMethod.create!(name: 'abc', admin_name: 'def') do |m|
          m.calculator = Spree::Calculator::Shipping::RetailopsAdvisory.new
          m.shipping_categories << Spree::ShippingCategory.first
        end

        ship.add_shipping_method(mm, true)
      end

      spree_xhr_post :add_packages, ap_package_dto
      expect(response.status).to eq(200)
    end

    it "can mark orders completely shipped" do
      o = create(:order_ready_to_ship, line_items_count: 1)
      o.shipments.first.inventory_units.each{ |iu| iu.order_id = o.id; iu.save! } # possibly a bug in the factory

      spree_xhr_post :add_packages, {
        "options"      => {},
        "order_refnum" => o.number,
        "packages"     => [
          {
            "contents" => [
              {
                "id"       => o.line_items.first.id,
                "quantity" => 1
              }
            ],
            "date"     => "2016-08-27T00:22:57Z",
            "from"     => "a location",
            "id"       => "584498",
            "shipcode" => "FedEx Ground",
            "tracking" => "846085121745341"
          }
        ]
      }
      expect(response.status).to eq(200)

      spree_xhr_post :mark_complete, {
        "options"      => {
          "ok_capture" => "true"
        },
        "order_refnum" => o.number,
        "refund_items" => []
      }
      expect(response.status).to eq(200)

      # mark_complete doesn't actually do much without refund handling, which we're explicitly punting (2016-08-29)
    end

    # it "can trigger payment refunds"
    # it "can issue order refunds"
    it "can call custom reimbursement handler" do
      o = create(:order_ready_to_ship)
      stub_const("RetailopsReimbursementHandler", Class.new)
      expect(RetailopsReimbursementHandler).to receive(:from_retailops_add_refund).and_return(Class.new do
        def create_reimbursement()
        end
      end.new)

      spree_xhr_post :add_refund, {
        "order_refnum" => o.number
      }
    end

    it "can perform payment commands"
    it "can cancel orders"
  end
end
