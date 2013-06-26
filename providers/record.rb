def whyrun_supported?
  true
end

def load_current_resource
  @route53 = RightAws::Route53Interface.new(@new_resource.aws_access_key_id, @new_resource.aws_secret_access_key)

  @zone_id = @new_resource.zone_id
  if @zone_id.nil? && !@new_resource.zone_name.nil?
    zone_name = @new_resource.zone_name
    zone_name += '.' unless zone_name[-1] == '.'
    Chef::Log.info "Looking up zone ID by name #{zone_name}"
    @zone_details = @route53.list_hosted_zones().find { |z| z[:name] == zone_name }
    raise "Unable to find zone ID by name #{@new_resource.zone_name}" if zone_details.nil?
    @zone_id = zone_details[:aws_id]
  else
    @zone_details = @route53.get_hosted_zone(@zone_id)
  end

  @record_fullname = "#{@new_resource.name}.#{@zone_details[:name]}"

  recordset = @route53.list_resource_record_sets(@zone_id)
  existing_record = recordset.find { |r| r[:name] == @record_fullname }

  @current_resource = Chef::Resource::Route53Record.new(@new_resource.name)
  if existing_record.nil?
    @current_resource.exists = false
  else
    @current_resource.exists = true
    @current_resource.zone_id(@zone_id)
    @current_resource.value(existing_record[:resource_records].join(','))
    @current_resource.type(existing_record[:type])
    @current_resource.ttl(existing_record[:ttl])
  end

end

action :create do
  if @current_resource.exists
    Chef::Log.info "Current resource: #{@current_resource} #{@current_resource.value}"
    Chef::Log.info "Not creating a new resource."
  else
    converge_by("Create #{@new_resource}") do
      Chef::Log.info "No such resource: #{@current_resource}"
      resource_record_sets = [{:name => @record_fullname,
                               :type => @new_resource.type,
                               :ttl => @new_resource.ttl,
                               :resource_records =>
                                   @new_resource.value.split(',').collect { |s| s.strip() }}]
      change_id = @route53.create_resource_record_sets(@zone_id, resource_record_sets)[:aws_id]
      pp @route53.get_change(change_id)[:status]
    end
  end
end
