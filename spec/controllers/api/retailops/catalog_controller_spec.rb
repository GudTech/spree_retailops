require 'spec_helper'

module Spree
  describe Spree::Api::Retailops::CatalogController do
    render_views
    before do
      stub_authentication!
    end

    context "as a random user" do
      it "cannot import catalog" do
        spree_post :catalog_push, products: [], format: :json
        assert_unauthorized!
      end
    end

    context "as an admin" do
      before { current_api_user.stub has_spree_role?: true }

      it "can do a no-op empty import" do
        spree_post :catalog_push, products: [], format: :json
        response.status.should == 200
        json_response['import_results'].should == []
      end

      it "can test 1" do
        expect_any_instance_of(Product).to receive(:retailops_extend_prodgood=).with('55')
        expect_any_instance_of(Variant).to receive(:retailops_extend_vargood=).with('77')
        spree_post :catalog_push, options: {}, products_json: <<EXAMPLE1
[
   {
      "available_on" : 1412121600,
      "corr_id" : "11",
      "cost_currency" : "USD",
      "cost_price" : 44,
      "description" : "This is a description",
      "images" : [
         {
            "alt_text" : "alt text 1",
            "extend" : {},
            "filename" : "img_1.jpg",
            "origin_url" : null,
            "url" : "https://media.gudtech.com/media/ZBzxWOGd1gGUrzYS8IJPfNGjinDUs3Lq-7.jpg"
         },
         {
            "alt_text" : "alt text 2",
            "extend" : {},
            "filename" : "img_2.jpg",
            "origin_url" : null,
            "url" : "https://media.gudtech.com/media/rF2A6lO2edsvvA7DUDPtEt8y9pUa7VYX-7.jpg"
         }
      ],
      "meta_desc" : "(Meta description)",
      "meta_keywords" : "",
      "name" : "product name",
      "options_used" : [
         "Color",
         "Size"
      ],
      "price" : 87.65,
      "prod_extend" : {
         "prodgood": "55",
         "prodbad": "66",
         "prodbad2": ""
      },
      "properties" : [
         {
            "key" : "MSRP",
            "value" : "123"
         },
         {
            "key" : "Oversized",
            "value" : "No"
         }
      ],
      "ship_category" : "Domestic and International",
      "sku" : "P40113",
      "slug" : "40113-sluggy",
      "tax_category" : "Sales and Use Tax",
      "taxa" : [
         [
            "Length",
            "Long"
         ]
      ],
      "variants" : [
         {
            "corr_id" : "2",
            "cost_price" : 1,
            "depth" : 0.1,
            "height" : 0.2,
            "images" : [],
            "options" : [
               {
                  "name" : "Color",
                  "value" : "Medium"
               },
               {
                  "name" : "Size",
                  "value" : "29"
               }
            ],
            "price" : 98.89,
            "sku" : "123654",
            "stock" : {
               "default" : 5
            },
            "stock_detailed" : {
               "all" : 5,
               "backorder" : {
                  "default" : false
               },
               "by_type" : {
                  "dropship" : 0,
                  "internal" : 5,
                  "jit" : 0
               }
            },
            "tax_category" : "Sales and Use Tax",
            "var_extend" : {
                "vargood" : "77"
            },
            "weight" : "0.5",
            "width" : 0.3
         }
      ],
      "varies" : true
   }
]
EXAMPLE1
        response.status.should == 200
        json_response['import_results'].should == [{
          'corr_id' => '11',
          'message' => 'Extension field prodbad (Spree::Product) not available on this instance',
        }]

        prod = Variant.where(sku: 'P40113').first.product

        prod.available_on.should == Time.at(1412121600)
        prod.master.cost_price.should == '44'.to_d
        prod.master.cost_currency.should == 'USD'
        prod.description.should == 'This is a description'

        prod.images.count.should == 2
        prod.images.first.position.should == 1
        prod.images.first.alt.should == 'alt text 1'
        prod.images.first.attachment_file_name.should == 'img_1.jpg'
        prod.images.first.attachment_file_size.should == 1058
        prod.images.second.position.should == 2
        prod.images.second.alt.should == 'alt text 2'
        prod.images.second.attachment_file_name.should == 'img_2.jpg'
        prod.images.second.attachment_file_size.should == 4025

        prod.meta_description.should == '(Meta description)'
        prod.meta_keywords.should == ''
        prod.name.should == 'product name'
        prod.option_types.pluck(:name).to_set.should == [ 'Color', 'Size' ].to_set
        prod.master.price.should == '87.65'.to_d
        # extends handled by the mock above ...
        prod.property('MSRP').should == '123'
        prod.property('Oversized').should == 'No'
        prod.shipping_category.name.should == 'Domestic and International'
        prod.master.sku.should == 'P40113' # redundant given search, but
        prod.slug.should == '40113-sluggy'
        prod.tax_category.name.should == 'Sales and Use Tax'
        prod.taxons.to_a.map(&:pretty_name).to_set.should == ['Length -> Long'].to_set

        prod.variants.size.should == 1
        vvar = prod.variants.first
        vvar.cost_price.should == '1'.to_d
        vvar.depth.should == '0.1'.to_d
        vvar.height.should == '0.2'.to_d

        vvar.images.count.should == 0

        vvar.option_values.size.should == 2
        vvar.option_value('Color').should == 'Medium'
        vvar.option_value('Size').should == '29'
        vvar.price.should == '98.89'.to_d
        vvar.sku.should == '123654'
        vvar.stock_items.sum(:count_on_hand).should == 5
        vvar.tax_category.name.should == 'Sales and Use Tax'
        vvar.width.should == '0.3'.to_d

        spree_post :catalog_push, options: {}, products_json: <<CHANGE
[
   {
      "corr_id" : "11",
      "description" : "This is also a description",
      "sku" : "P40113",
      "varies" : true
   }
]
CHANGE
        response.status.should == 200
        json_response['import_results'].should == []

        prod = Variant.where(sku: 'P40113').first.product
        prod.description.should == 'This is also a description'
        prod.property('MSRP').should == '123'
      end
    end
  end
end
