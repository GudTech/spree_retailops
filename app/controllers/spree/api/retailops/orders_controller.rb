module Spree
  module Api
    module Retailops
      class OrdersController < Spree::Api::BaseController
        # This function handles fetching order data for RetailOps.  In the spirit of
        # pushing as much maintainance burden as possible onto RetailOps and not
        # requiring different versions per client, we return data in a fairly raw
        # state.  This also needs to be relatively fast.  Since we cannot guarantee
        # that the other side will receive and correctly process the data we return
        # (there might be a badly timed network dropout, or *gasp* a bug), we don't
        # mark orders as exported here - that's handled in export below.

        module Extractor
          INCLUDE_BLOCKS = {}
          LOOKUP_LISTS = {}

          def self.use_association(klass, syms, included = true)
            syms.each do |sym|
              to_assoc = klass.reflect_on_association(sym) or next
              to_incl_block = to_assoc.polymorphic? ? {} : (INCLUDE_BLOCKS[to_assoc.klass] ||= {})
              incl_block = INCLUDE_BLOCKS[klass] ||= {}
              incl_block[sym] = to_incl_block
              (LOOKUP_LISTS[klass] ||= {})[sym] = true if included
            end
          end

          def self.ad_hoc(klass, sym, need = [])
            use_association klass, need, false
            (LOOKUP_LISTS[klass] ||= {})[sym] = Proc.new
          end

          use_association Order, [:line_items, :adjustments, :shipments, :ship_address, :bill_address, :payments]

          use_association LineItem, [:adjustments]
          ad_hoc(LineItem, :sku, [:variant]) { |i| i.variant.try(:sku) }
          ad_hoc(LineItem, :advisory, [:variant]) { |i| p = i.variant.try(:product); i.try(:retailops_is_advisory?) || p.try(:retailops_is_advisory?) || p.try(:is_gift_card) }
          ad_hoc(LineItem, :expected_ship_date, []) { |i| i.try(:retailops_expected_ship_date) }

          use_association Variant, [:product], false

          use_association Shipment, [:adjustments]
          ad_hoc(Shipment, :shipping_method_name, [:shipping_rates]) { |s| s.shipping_method.try(:name) }

          use_association ShippingRate, [:shipping_method], false

          ad_hoc(Address, :state_text, [:state]) { |a| a.state_text }
          ad_hoc(Address, :country_iso, [:country]) { |a| a.country.try(:iso) }

          use_association Payment, [:source]
          ad_hoc(Payment, :method_class, [:payment_method]) { |p| p.payment_method.try(:type) }

          def self.walk_order_obj(o)
            ret = {}
            o.class.column_names.each { |cn| ret[cn] = o.public_send(cn).as_json }
            if list = LOOKUP_LISTS[o.class]
              list.each do |sym, block|
                if block.is_a? Proc
                  ret[sym.to_s] = block.call(o)
                else
                  relat = o.public_send(sym)
                  if relat.is_a? ActiveRecord::Relation
                    relat = relat.map { |rec| walk_order_obj rec }
                  elsif relat.is_a? ActiveRecord::Base
                    relat = walk_order_obj relat
                  end
                  ret[sym.to_s] = relat
                end
              end
            end
            return ret
          end

          def self.root_includes
            INCLUDE_BLOCKS[Order] || {}
          end
        end

        def index
          authorize! :read, [Order, LineItem, Variant, Payment, PaymentMethod, CreditCard, Shipment, Adjustment]

          query = options['filter'] || {}
          query['completed_at_not_null'] ||= 1
          query['retailops_import_eq'] ||= 'yes'
          results = Order.ransack(query).result.limit(params['limit'] || 50).includes(Extractor.root_includes)

          render text: results.map { |o|
            begin
              Extractor.walk_order_obj(o)
            rescue Exception => ex
              Rails.logger.error("Order export failed: #{ex.to_s}:\n  #{ex.backtrace * "\n  "}")
              { "error" => ex.to_s, "trace" => ex.backtrace, "number" => o.number }
            end
          }.to_json
        end

        def export
          authorize! :update, Order
          ids = params["ids"]
          raise "ids must be a list of numbers" unless ids.is_a?(Array) && ids.all? { |i| i.is_a? Fixnum }

          missing_ids = ids - Order.where(id: ids, retailops_import: ['done', 'yes']).pluck(:id)
          raise "order IDs could not be matched or marked nonimportable: " + missing_ids.join(', ') if missing_ids.any?

          Order.where(retailops_import: 'yes', id: ids).update_all(retailops_import: 'done')
          render text: {}.to_json
        end

        # This probably calls update! far more times than it needs to as a result of line item hooks, etc
        # Exercise for interested parties: fix that
        #
        # Here are example parameters
        #
        #
        # {
        #   "order_amts" => {
        #     "shipping_amt" => 4.98,
        #     "discount_amt" => 0,
        #     "tax_amt" => 0,
        #     "direct_tax_amt" => 0
        #   },
        #   "rmas" => nil,
        #   "line_items" => [
        #     {
        #       "estimated_extended_cost" => "27.50",
        #       "apportioned_ship_amt" => 4.98,
        #       "sku" => "136270",
        #       "quantity" => "1",
        #       "estimated_ship_date" => 1458221964,
        #       "direct_ship_amt" => 0,
        #       "corr" => "575714",
        #       "removed" => nil,
        #       "estimated_cost" => 27.5,
        #       "estimated_unit_cost" => 27.5,
        #       "unit_price" => 49.98
        #     }
        #   ],
        #   "options" => {},
        #   "order_refnum" => "R280725117",
        #   "order" => {}
        # }
        #
        def synchronize
          authorize! :update, Order
          changed = false
          result = []
          order = Order.find_by!(number: params["order_refnum"].to_s)
          @helper = Spree::Retailops::RopOrderHelper.new
          @helper.order = order
          @helper.options = options
          ActiveRecord::Base.transaction do
            # RetailOps will be sending in an authoritative (potentially updated) list of line items
            # We make our data match that as well as possible, and then send the list back annotated
            # with channel_refnums and quantities/costs/etc

            if defined?(RetailopsLineItemUpdateHandler)
              line_items_changed, line_items_result = RetailopsLineItemUpdateHandler.new(order, params["line_items"].to_a).call
            else
              line_items_changed, line_items_result = Spree::Retailops::RopLineItemUpdater.new(order, params["line_items"].to_a).call
            end

            changed = true if line_items_changed
            result = result + line_items_result

            items_changed = changed
            order.all_adjustments.tax.each { |a| a.close if a.open? } # Allow tax to organically recalculate

            # omitted RMAs are treated as 'no action'
            params["rmas"].to_a.each do |rma|
              changed = true if sync_rma order, rma
            end

            ro_amts = params['order_amts'] || {}
            if options["ro_authoritative_ship"]
              if ro_amts["shipping_amt"]
                total = ro_amts["shipping_amt"].to_d
                item_level = 0.to_d + params['line_items'].to_a.collect{ |l| l['direct_ship_amt'].to_d }.sum
                changed = true if @helper.apply_shipment_price(total, total - item_level)
              end
            elsif items_changed
              calc_ship = @helper.calculate_ship_price
              # recalculate and apply ship price if we still have enough information to do so
              # calc_ship may be nil otherwise
              @helper.apply_shipment_price(calc_ship) if calc_ship
            end

            if changed
              # Allow tax to organically recalculate
              # *slightly* against the spirit of adjustments to automatically reopen them, but this is triggered on item changes which are (generally) human-initiated in RO
              if items_changed
                order.all_adjustments.tax.each { |a| a.open if a.closed? }
                order.adjustments.promotion.each { |a| a.open if a.closed? }
              end

              order.update!

              order.all_adjustments.tax.each { |a| a.close if a.open? }
              order.adjustments.promotion.each { |a| a.close if a.open? }
            end


            if order.respond_to?(:retailops_after_writeback)
              order.retailops_after_writeback(params)
            end

            order.update! if changed
          end

          render text: {
            changed: changed,
            dump: Extractor.walk_order_obj(order),
            result: result,
          }.to_json
        end

        def sync_rma(order, rma)
          # This is half of the RMA/return push mechanism: it handles RMAs created in RetailOps by
          # creating matching RMAs in Spree numbered RMA-ROP-NNN.  Any inventory which has been
          # returned in RetailOps will have a corresponding RetailOps return; if that exists in
          # Spree, then we *exclude* that inventory from the RMA being created and delete the RMA
          # when all items are removed.

          # find Spree RMA.  bail out if received (shouldn't happen)
          return unless order.shipped_shipments.any?  # avoid RMA create failures
          rop_rma_str = "RMA-RO-#{rma["id"].to_i}"
          rma_obj = order.return_authorizations.detect { |r| r.number == rop_rma_str }
          return if rma_obj && rma_obj.received?

          # for each ROP return: check if it exists in Spree.  Reduce RMA amount for returns that
          # have been filed.

          closed_value = 0.to_d
          closed_items = {}

          rma["returns"].to_a.each do |ret|
            ret_str = "RMA-RET-#{ret["id"].to_i}"
            ret_obj = order.return_authorizations.detect { |r| r.number == ret_str }

            if ret_obj && ret_obj.received?
              closed_value += ret['refund_amt'].to_d - (ret['tax_amt'] ? (ret['tax_amt'].to_d + ret['shipping_amt'].to_d) : 0)
              ret["items"].to_a.each do |it|
                it_obj = order.line_items.detect { |i| i.id.to_s == it["channel_refnum"].to_s }
                closed_items[it_obj] = (closed_items[it_obj] || 0) + it["quantity"].to_i if it_obj
              end
            end
          end

          use_items = {}
          use_total = 0

          rma["items"].to_a.each do |it|
            line = order.line_items.detect { |i| i.id.to_s == it["channel_refnum"].to_s } or next
            use_items[line] = [ 0, it["quantity"].to_i - (closed_items[line] || 0) ].max
          end

          use_items.each do |li, qty|
            use_total += qty
          end

          # create RMA if not exists and items > 0
          return if !rma_obj && use_total <= 0

          unless rma_obj
            rma_obj = order.return_authorizations.build
            rma_obj.number = rop_rma_str
            rma_obj.save! # have an ID *before* adding items
            changed = true
          end

          # set RMA item quantities

          changed = false

          order.line_items.each do |li|
            # this function is misnamed, it sets, it does not add
            changed = true # use rma_obj.inventory_units to identify changes if it ever becomes necessary
            rma_obj.add_variant(li.variant_id, use_items[li] || 0)
          end

          # delete RMA if all items gone
          if use_total == 0
            rma_obj.destroy!
            return true
          end

          # set RMA amount
          if rma["subtotal_amt"].present? || rma["refund_amt"].present?
            use_value = rma['refund_amt'].to_d - (rma['tax_amt'] ? (rma['tax_amt'].to_d + rma['shipping_amt'].to_d) : 0) - closed_value
            if use_value != rma_obj.amount
              rma_obj.amount = use_value
              changed = true
            end
          end

          rma_obj.save! if changed
          return true
        end

        private
          def options
            params['options'] || {}
          end
      end
    end
  end
end
