require 'chef/provider/lwrp_base'
require_relative 'helpers_debian'
require 'shellwords'

class Chef
  class Provider
    class MysqlService
      class Debian < Chef::Provider::MysqlService
        use_inline_resources if defined?(use_inline_resources)

        def whyrun_supported?
          true
        end

        include MysqlCookbook::Helpers::Debian

        action :create do
          package "#{new_resource.parsed_name} :create mysql" do
            package_name new_resource.parsed_package_name
            action :install
          end

          # We're not going to use the "system" mysql service, but
          # instead create a bunch of new ones based on resource names.
          service "#{new_resource.parsed_name} :create #{mysql_name}" do
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
          directory "#{new_resource.parsed_name} :create #{run_dir}" do
            path run_dir
            owner new_resource.parsed_run_user
            group new_resource.parsed_run_group
            mode '0755'
            action :create
            recursive true
          end

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

          directory "#{new_resource.parsed_name} :create #{new_resource.parsed_data_dir}" do
            path new_resource.parsed_data_dir
            owner new_resource.parsed_run_user
            group new_resource.parsed_run_group
            mode '0750'
            recursive true
            action :create
          end

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
            # notifies :restart, "service[#{new_resource.parsed_name} :create #{mysql_name}]"
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

          # service
          template "/etc/#{mysql_name}/debian.cnf" do
            cookbook 'mysql'
            source 'debian/debian.cnf.erb'
            owner 'root'
            group 'root'
            mode '0600'
            variables(
              :config => new_resource,
              :socket_file => socket_file
              )
            action :create
          end

          # init script
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

          template "#{new_resource.parsed_name} :create /etc/#{mysql_name}/debian-start" do
            path "/etc/#{mysql_name}/debian-start"
            cookbook 'mysql'
            source 'debian/debian-start.erb'
            owner 'root'
            group 'root'
            mode '0755'
            variables(
              :config => new_resource,
              :mysql_name => mysql_name,
              :socket_file => socket_file
              )
            action :create
          end
          
          service "#{new_resource.parsed_name} :create #{mysql_name}" do
            service_name mysql_name
            provider Chef::Provider::Service::Init
            supports :restart => true, :status => true
            action [:start]
          end

          ruby_block "#{new_resource.parsed_name} :create set mysql database charset" do
            block do
              alter_mysql_password_charset
            end
            not_if { mysql_password_charset == 'utf8' }
            action :run
          end

          ruby_block "#{new_resource.parsed_name} :create set debian-sys-maint" do
            block do
              set_debian_sys_maint
            end
            not_if { test_debian_sys_maint }
            action :run
          end

          ruby_block "#{new_resource.parsed_name} :create set root password" do
            block do
              set_root_password
            end
            not_if { test_root_password }
            action :run
          end         

          # template "#{new_resource.parsed_name} :create /etc/#{mysql_name}/grants.sql" do
          #   path "/etc/#{mysql_name}/grants.sql"
          #   cookbook 'mysql'
          #   source 'grants/grants.sql.erb'
          #   owner 'root'
          #   group 'root'
          #   mode '0600'
          #   variables(:config => new_resource)
          #   action :create
          #   notifies :run, "execute[#{new_resource.parsed_name} :create install-grants]"
          # end

          # execute "#{new_resource.parsed_name} :create install-grants" do
          #   cmd = '/usr/bin/mysql'
          #   cmd << ' -u root '
          #   cmd << "#{pass_string} < /etc/#{mysql_name}/grants.sql"
          #   command cmd
          #   action :nothing
          #   notifies :run, "execute[#{new_resource.parsed_name} :create root marker]"
          # end

          # execute "#{new_resource.parsed_name} :create root marker" do
          #   cmd = '/bin/echo'
          #   cmd << " '#{Shellwords.escape(new_resource.parsed_server_root_password)}'"
          #   cmd << " > /etc/#{mysql_name}/.mysql_root"
          #   cmd << " ;/bin/chmod 0600 /etc/#{mysql_name}/.mysql_root"
          #   command cmd
          #   action :nothing
          # end
        end
      end

      action :restart do
        service 'mysql' do
          service_name mysql_name
          provider Chef::Provider::Service::Init::Debian
          supports :restart => true
          action :restart
        end
      end

      action :reload do
        service 'mysql' do
          service_name mysql_name
          provider Chef::Provider::Service::Init::Debian
          action :reload
        end
      end
    end
  end
end
