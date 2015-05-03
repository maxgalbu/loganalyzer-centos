group { 'puppet': ensure => present }
Exec { path => [ '/bin/', '/sbin/', '/usr/bin/', '/usr/sbin/' ] }


service { 'iptables':
	ensure => stopped,
}

file { "/etc/localtime":
	source => "file:///usr/share/zoneinfo/Europe/Rome",
	require => Package["tzdata"]
}

file_line { 'change $PS1 colors':
	ensure => 'present',
	path => '/home/vagrant/.bashrc',
	line => 'PS1="\[$(tput bold)\][\[$(tput setaf 1)\]\u\[$(tput setaf 4)\]@\h\[$(tput setaf 3)\] \W]\[$(tput setaf 7)\]\\$\[$(tput sgr0)\] "',
}

class { 'yum':
	extrarepo => [ 'epel' , 'rpmforge' ],
}
class yum::repo::elasticsearch13 {
	yum::managed_yumrepo { 'elasticsearch-1.3':
		descr          => 'Elasticsearch repository for 1.3.x packages',
		baseurl        => 'http://packages.elasticsearch.org/elasticsearch/1.3/centos',
		enabled        => 1,
		gpgcheck       => 1,
		gpgkey         => 'http://packages.elasticsearch.org/GPG-KEY-elasticsearch',
	}
}
class yum::repo::logstash14 {
	yum::managed_yumrepo { 'logstash-1.4':
		descr          => 'logstash repository for 1.4.x packages',
		baseurl        => 'http://packages.elasticsearch.org/logstash/1.4/centos',
		enabled        => 1,
		gpgcheck       => 1,
		gpgkey         => 'http://packages.elasticsearch.org/GPG-KEY-elasticsearch',
	}
}

include yum::repo::elasticsearch13
include yum::repo::logstash14

$packagelist = [
	'curl',
	'mc',
	'augeas',
	'tzdata',
	'ruby',
	'ruby-devel',
	'java-1.7.0-openjdk',
	'openssl'
]
package { $packagelist:
	ensure  => 'installed',
	require => Class['yum'],
}
package { 'nginx':
	ensure => 'installed',
	require => Class['yum::repo::epel'],
}
package { 'elasticsearch':
	ensure  => 'installed',
	require => Class['yum::repo::elasticsearch13'],
}
package { 'logstash':
	ensure  => 'installed',
	require => Class['yum::repo::logstash14'],
}

service { 'elasticsearch':
	ensure => 'running',
	require => Package['elasticsearch'],
}
service { 'nginx':
	ensure => 'running',
	require => Package['nginx'],
}
service { 'logstash':
	ensure => 'running',
	require => Package['logstash'],
}

#Elasticsearch config
file_line { 'elasticsearch config 1':
	path  => '/etc/elasticsearch/elasticsearch.yml',
	line  => 'script.disable_dynamic: true',
	require => Package['elasticsearch'],
	notify  => Service['elasticsearch'],
}
file_line { 'elasticsearch config 2':
	path  => '/etc/elasticsearch/elasticsearch.yml',
	line => 'discovery.zen.ping.multicast.enabled: false',
	match => '#?\s*discovery\.zen\.ping\.multicast\.enabled: false',
	require => Package['elasticsearch'],
	notify  => Service['elasticsearch'],
}
file_line { 'elasticsearch config 3':
	path  => '/etc/elasticsearch/elasticsearch.yml',
	line => 'network.host: localhost',
	match => '#?network.host:\s*[0-9a-zA-Z\.]',
	require => Package['elasticsearch'],
	notify  => Service['elasticsearch'],
}

#Nginx config
file { '/etc/nginx/conf.d/default.conf':
	source => "file:///vagrant/files/nginx-default.conf",
	require => Package[$packagelist],
	notify  => Service['nginx'],
}

#Logstash certs
exec { 'create logstash certs':
	command => "openssl req -x509 -batch -nodes -days 3650 -newkey rsa:2048 -keyout private/logstash-forwarder.key -out certs/logstash-forwarder.crt",
	cwd => "/etc/pki/tls",
	user => root,
	creates => "/etc/pki/tlscerts/logstash-forwarder.crt",
	require => Package[$packagelist],
}

#Logstash config
file { '/etc/logstash/conf.d/01-lumberjack-input.conf':
	source	=> "file:///vagrant/files/01-lumberjack-input.conf",
	require => Package['logstash'],
	notify  => Service['logstash'],
}
file { '/etc/logstash/conf.d/10-syslog.conf':
	source	=> "file:///vagrant/files/10-syslog.conf",
	require => Package['logstash'],
	notify  => Service['logstash'],
}
file { '/etc/logstash/conf.d/30-lumberjack-output.conf':
	source	=> "file:///vagrant/files/30-lumberjack-output.conf",
	require => Package['logstash'],
	notify  => Service['logstash'],
}

#Install kibana
define tarball($pkg_tgz, $install_dir, $require=undef) {
	# create the install directory
	file { "$install_dir":
		ensure => directory,
		require => $require,
	}

	# download the tgz file
	file { "$pkg_tgz":
		path => "/tmp/$pkg_tgz",
		source => "file:///vagrant/files/$pkg_tgz",
		notify => Exec["untar $pkg_tgz"],
	}

	# untar the tarball at the desired location
	exec { "untar $pkg_tgz":
		user => root,
		refreshonly => true,
		command => "rm -rf $install_dir/*; tar xzvf /tmp/$pkg_tgz -C $install_dir/ --strip 1",
		require => File["/tmp/$pkg_tgz", "$install_dir"],
	}
}

tarball { 'untar kibana':
	install_dir => "/usr/share/nginx/kibana3",
	pkg_tgz => "kibana-3.1.0.tar.gz",
	require => Package['nginx'],
}
file { '/usr/share/nginx/kibana3/config.js':
	source	=> "file:///vagrant/files/kibana-config.js",
	require => Tarball['untar kibana'],
}
