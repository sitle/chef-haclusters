#
# Cookbook Name:: chef-haclusters
# Recipe:: default
#
# Copyright (C) 2014 PE, pf.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# PE-20140916
include_recipe 'haproxy::default'

begin
  raise unless haDefinition= data_bag_item('clusters', node['fqdn'].gsub(".", "_"))
  rescue Exception
    puts '********************************************************************'
    puts 'This node name is not defined for such a role (procedure aborted)...'
    puts '********************************************************************'
    return
  ensure
  #
end

def sumEnv(env, add)
  add.each do |name, val|
    if val.is_a? Hash
      env[name] = sumEnv(env[name], val)
    else
      if val.is_a? Array
        env[name] = env[name] ? env[name] + val : val
      else
        env[name] = val if ! env[name]
      end
    end
  end
  env
end

if haDefinition != {} && haDefinition["haproxy"] != {}
  haDefinition = haDefinition["haproxy"]

  include_recipe "haproxy::install_#{node['haproxy']['install_method']}"
  cookbook_file "/etc/default/haproxy" do
    source "haproxy-default"
    owner "root"
    group "root"
    mode 00644
    notifies :restart, "service[haproxy]", :delayed
  end

# Admin definition:
  admin = haDefinition['enable_admin'] ? haDefinition['admin'] : node['haproxy']['admin']

  if admin
    haproxy_lb "admin" do
      bind "#{admin['address_bind']}:#{admin['port']}"
      mode 'http'
      params(admin['options'])
    end
  end

# For each service:
  haDefinition['services'].each do |serviceName, serviceDefinition|

    # getenv(others nodes['app_server_role'] definitions):
    if serviceDefinition['app_server_role']
      data_bag('clusters').each do |item|
        if item != node['fqdn'].gsub(".", "_")
          i = data_bag_item('clusters', item)['haproxy']
          i = i['services'] if i
          i = i[serviceName] if i
          if i && i['app_server_role'] == serviceDefinition['app_server_role']
            serviceDefinition = sumEnv( serviceDefinition, i )
          end
        end
      end
    end

    # Frontend definition:
    if serviceDefinition['mode']
         mode = serviceDefinition['mode']
    else mode = node['haproxy']['mode']
    end

    if serviceDefinition['frontend_max_connections']
         maxconn = serviceDefinition['frontend_max_connections']
    else maxconn = node['haproxy']['frontend_max_connections']
    end

    if serviceDefinition['incoming_address']
         incoming_address = serviceDefinition['incoming_address']
    else incoming_address = node['haproxy']['incoming_address']
    end

    if serviceDefinition['incoming_address']
         incoming_port = serviceDefinition['incoming_port']
    else incoming_port = node['haproxy']['incoming_port']
    end

    haproxy_lb "#{serviceName}" do
      type 'frontend'
      mode "#{mode}"
      params({
      'maxconn' => maxconn,
      'bind' => "#{incoming_address}:#{incoming_port}",
      'default_backend' => "servers-#{serviceName}"
      })
    end

  # Backend definition:
    if serviceDefinition['httpchk']
         pool = ["option httpchk #{serviceDefinition['httpchk']}"]
    else pool = ["option httpchk #{node['haproxy']['httpchk']}"]
    end

    if serviceDefinition['pool_members'] != {}
         pool_members = serviceDefinition['pool_members']
    else pool_members = node['haproxy']['pool_members']
    end

    if pool_members
      servers = pool_members.uniq.map do |s|
        server = "#{s['hostname']} #{s['ipaddress']}"

        if ! s['member_port']
             server += ":#{node['haproxy']['member_port']}"
        else server += ":#{s['member_port']}"
        end

        if ! s['member_options']
              server += " weight 1 maxconn #{node['haproxy']['member_max_connections']} check"
        else server += " #{s['member_options']}"
        end

        server
      end
    end

    haproxy_lb "servers-#{serviceName}" do
      type 'backend'
      mode "#{mode}"
      balance serviceDefinition['balance'] if serviceDefinition['balance']
      servers servers
      params pool
    end

    if serviceDefinition['enable_ssl']==true || ( serviceDefinition['enable_ssl']==nil && node['haproxy']['enable_ssl'])
      pool  = ["option ssl-hello-chk"]
      if serviceDefinition['ssl_httpchk']
           pool << ["option httpchk #{serviceDefinition['ssl_httpchk']}"]
      else pool << ["option httpchk #{node['haproxy']['ssl_httpchk']}"]
      end

      servers= pool_members.uniq.map do |s|
        server  = "#{s['hostname']} #{s['ipaddress']}"

        if ! s['member_ssl_port']
             server += ":#{node['haproxy']['ssl_member_port']}"
        else server += ":#{s['member_ssl_port']}"
        end

        if ! s['member_ssl_options']
             server += " weight 1 maxconn #{node['haproxy']['member_max_connections']} check"
        else server += " #{s['member_options']}"
        end

        server
      end

     if serviceDefinition['mode']
          mode = serviceDefinition['mode']
     else mode =  node['haproxy']['mode']
     end

     haproxy_lb "servers-#{mode}" do
       type 'backend'
       mode "#{mode}"
       servers servers
       params pool
     end
   end

  end if haDefinition != {}

  haproxy_config "Create haproxy.cfg" do
    notifies :restart, "service[haproxy]", :delayed
  end

end
