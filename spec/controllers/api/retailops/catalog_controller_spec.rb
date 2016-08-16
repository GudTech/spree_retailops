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
        spree_post :catalog_push, options: {}, products_json: <<EXAMPLE1
[
   {
      "available_on" : 1412121600,
      "corr_id" : "1",
      "cost_currency" : "",
      "cost_price" : 0,
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
      "permalink" : "40113-sluggy",
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
            "depth" : 0,
            "height" : 0,
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
            },
            "weight" : 0.5,
            "width" : 0
         }
      ],
      "varies" : true
   }
]
EXAMPLE1
        #foo
        response.status.should == 200
        puts(JSON.pretty_generate(json_response['import_results']))
        v = Variant.where(sku: 'P40113').first
        prod = v.product
        prod.description.should == 'This is a description'
        prod.slug.should == '40113-sluggy'
        prod.meta_description.should == '(Meta description)'
      end
    end
  end
end
