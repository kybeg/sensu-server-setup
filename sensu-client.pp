
# VARIABLES
########################################################

$RABBITMQ_PASSWD = "398hhgaihdliauhe893"

$ADMIN_PASSWD = "sensuadminpass"

$SENSU_SERVER_IP = "INSERT_SENSU_SERVER_IP_HERE"

########################################################


$SENSU_CONFIG = "
{
      \"rabbitmq\": {
        \"ssl\": {
          \"private_key_file\": \"/etc/sensu/ssl/client_key.pem\",
          \"cert_chain_file\": \"/etc/sensu/ssl/client_cert.pem\"
        },
        \"port\": 5671,
        \"host\": \"$SENSU_SERVER_IP\",
        \"user\": \"sensu\",
        \"password\": \"$RABBITMQ_PASSWD\",
        \"vhost\": \"/sensu\"
      }
     }
"


$SENSU_CLIENT_CONFIG = "
{
\"client\":{
\"name\":\"$hostname\",
\"address\":\"$ipaddress\",
\"subscriptions\":[\"test\"]
}
}
"

# REDIS

package { "redis-server" :
 ensure => present,
}

service { "redis-server" :
  ensure => running,
  require => Package['redis-server'],
}


# SENSU
     exec { "add-sensu-repo-key" :
             path => "/usr/bin/:/usr/sbin/:/usr/local/bin:/bin/:/sbin",
             command => "curl http://repos.sensuapp.org/apt/pubkey.gpg | apt-key add - ",
             unless => "ls /etc/apt/sources.list.d/sensu.list",
	     require => Package['redis-server'],
     }

     exec { "add-sensu-repo" :
             path => "/usr/bin/:/usr/sbin/:/usr/local/bin:/bin/:/sbin",
             command => "echo ' deb     http://repos.sensuapp.org/apt sensu main' >> /etc/apt/sources.list.d/sensu.list ; apt-get update",
             require => Exec["add-sensu-repo-key"],
             unless => "ls /etc/apt/sources.list.d/sensu.list"
     }

    package { "sensu" :
      ensure => present,
      require => Exec['add-sensu-repo'],
      }
    
    file { "/etc/sensu/ssl" :
      ensure => directory,
      mode => 644,
      require => Package['sensu'],
     }
     
    
   file { "/etc/sensu/conf.d/client.json":
     ensure => present,
     content => $SENSU_CLIENT_CONFIG,
     require => File['/etc/sensu/ssl'],
     notify => Service['sensu-client'],
   }
   
    
