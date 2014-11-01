require 'chef/provider/lwrp_base'
require 'shellwords'
require_relative 'helpers_debian'

class Chef
  class Provider
    class MysqlService
      class Debian < Chef::Provider::MysqlService
        use_inline_resources if defined?(use_inline_resources)

        def whyrun_supported?
          true
        end

        include MysqlCookbook::Helpers
        include MysqlCookbook::Helpers::Debian

        action :create do
          package "#{new_resource.parsed_name} :create mysql" do
            package_name new_resource.parsed_package_name
            action :install
          end

          # We're not going to use the "system" mysql service, but
          # instead create a bunch of new ones based on resource names.
          service "#{new_resource.parsed_name} :create mysql" do
            service_name 'mysql'
            provider Chef::Provider::Service::Init
            supports :restart => true, :status => true
            action [:stop, :disable]
          end

          # Turns out that mysqld is hard coded to try and read
          # /etc/mysql/my.cnf, and its presence causes problems when
          # setting up multiple services.
          file "#{new_resource.parsed_name} :create /etc/mysql/my.cnf" do
            path '/etc/mysql/my.cnf'
            action :delete
          end

          file "#{new_resource.parsed_name} :create /etc/my.cnf" do
            path '/etc/my.cnf'
            action :delete
          end

          group "#{new_resource.parsed_name} :create #{new_resource.parsed_run_group}" do
            group_name new_resource.parsed_run_group
            action :create
          end

          user "#{new_resource.parsed_name} :create #{new_resource.parsed_run_user}" do
            username new_resource.parsed_run_user
            gid new_resource.parsed_run_user
            action :create
          end

          # support directories
          directory "#{new_resource.parsed_name} :create /etc/#{mysql_name}" do
            path "/etc/#{mysql_name}"
            owner new_resource.parsed_run_user
            group new_resource.parsed_run_group
            mode '0750'
            recursive true
            action :create
          end

          directory "#{new_resource.parsed_name} :create #{include_dir}" do
            path include_dir
            owner new_resource.parsed_run_user
            group new_resource.parsed_run_group
            mode '0750'
            recursive true
            action :create
          end

          directory "#{new_resource.parsed_name} :create #{run_dir}" do
            path run_dir
            owner new_resource.parsed_run_user
            group new_resource.parsed_run_group
            mode '0755'
            action :create
            recursive true
          end

          directory "#{new_resource.parsed_name} :create #{new_resource.parsed_data_dir}" do
            path new_resource.parsed_data_dir
            owner new_resource.parsed_run_user
            group new_resource.parsed_run_group
            mode '0750'
            recursive true
            action :create
          end

          directory "#{new_resource.parsed_name} :create /var/log/#{mysql_name}" do
            path "/var/log/#{mysql_name}"
            owner new_resource.parsed_run_user
            group new_resource.parsed_run_group
            mode '0750'
            recursive true
            action :create
          end

          # FIXME: pass new_resource as config
          template "#{new_resource.parsed_name} :create /etc/#{mysql_name}/my.cnf" do
            path "/etc/#{mysql_name}/my.cnf"
            source "#{new_resource.parsed_version}/my.cnf.erb"
            cookbook 'mysql'
            owner new_resource.parsed_run_user
            group new_resource.parsed_run_group
            mode '0600'
            variables(
              :run_user => new_resource.parsed_run_user,
              :data_dir => new_resource.parsed_data_dir,
              :pid_file => pid_file,
              :socket_file => socket_file,
              :port => new_resource.parsed_port,
              :include_dir => include_dir
              )
            action :create
          end

          # initialize mysql database
          bash "#{new_resource.parsed_name} :create initialize mysql database" do
            user new_resource.parsed_run_user
            cwd new_resource.parsed_data_dir
            code <<-EOF
            /usr/bin/mysql_install_db \
             --basedir=/usr \
             --defaults-file=/etc/#{mysql_name}/my.cnf \
             --datadir=#{new_resource.parsed_data_dir} \
             --user=#{new_resource.parsed_run_user}
            EOF
            not_if "/usr/bin/test -f #{new_resource.parsed_data_dir}/mysql/user.frm"
            action :run
          end
        end

        action :delete do
          template "#{new_resource.parsed_name} :create /etc/init.d/#{mysql_name}" do
            path "/etc/init.d/#{mysql_name}"
            source "#{mysql_version}/sysvinit/#{platform_and_version}/mysql.erb"
            owner 'root'
            group 'root'
            mode '0755'
            variables(
              :mysql_name => mysql_name,
              :data_dir => new_resource.parsed_data_dir
              )
            cookbook 'mysql'
            action :create
          end

          service "#{new_resource.parsed_name} :delete #{mysql_name}" do
            service_name mysql_name
            provider Chef::Provider::Service::Init
            supports :restart => true, :status => true
            action [:stop]
          end

          directory "#{new_resource.parsed_name} :delete /etc/#{mysql_name}" do
            path "/etc/#{mysql_name}"
            recursive true
            action :delete
          end

          directory "#{new_resource.parsed_name} :delete #{run_dir}" do
            path run_dir
            recursive true
            action :delete
          end

          directory "#{new_resource.parsed_name} :delete /var/log/#{mysql_name}" do
            path "/var/log/#{mysql_name}"
            recursive true
            action :delete
          end
        end

        action :start do
          template "#{new_resource.parsed_name} :create /etc/init.d/#{mysql_name}" do
            path "/etc/init.d/#{mysql_name}"
            source "#{mysql_version}/sysvinit/#{platform_and_version}/mysql.erb"
            owner 'root'
            group 'root'
            mode '0755'
            variables(
              :mysql_name => mysql_name,
              :mysqld_safe_bin => mysqld_safe_bin,
              :data_dir => new_resource.parsed_data_dir,
              :pid_file => pid_file,
              :port => new_resource.parsed_port,
              :socket_file => socket_file,
              :run_user => new_resource.parsed_run_user,
              :base_dir => base_dir
              )
            cookbook 'mysql'
            action :create
          end

          service "#{new_resource.parsed_name} :start #{mysql_name}" do
            service_name mysql_name
            provider Chef::Provider::Service::Init
            supports :restart => true, :status => true
            action [:start]
          end
        end

        action :stop do
          service "#{new_resource.parsed_name} :stop #{mysql_name}" do
            service_name mysql_name
            provider Chef::Provider::Service::Init
            supports :restart => true, :status => true
            action [:stop]
          end
        end

        action :restart do
          service "#{new_resource.parsed_name} :restart #{mysql_name}" do
            service_name mysql_name
            provider Chef::Provider::Service::Init
            supports :restart => true
            action :restart
          end
        end

        action :reload do
          service "#{new_resource.parsed_name} :reload #{mysql_name}" do
            service_name mysql_name
            provider Chef::Provider::Service::Init
            action :reload
          end
        end
      end
    end
  end
end
