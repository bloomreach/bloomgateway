# BloomGateway (Version 0.10.5)
[![Join the chat at https://gitter.im/bloomreach/bloomgateway](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/bloomreach/bloomgateway?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)
Ronak Kothari (ronak.kothari@gmail.com)

## Overview

BloomGateway is a lightweight entry point service which helps in controlling edge service requirements in distributed environment. It is designed to provide high availability, high performance and low latency for mediating service requests. It supports a simple pluggable module architecture for extending service for addressing diverse needs with minimal efforts.

At [BloomReach](http://www.bloomreach.com), we used this in front of our public facing as well as internal facing infrastructure.

### Architecture

To provide high performace edge service solution, we are using [OpenResty](https://openresty.org/en/getting-started.html) as our underlying engine which is nothing but [Nginx](https://www.nginx.com/) + [Lua](https://www.lua.org/). On top of that, we are having our core engine which controls initialization and execution workflow of different plugins, provides pull as well as push model for updating configs at runtime, and supports health checks functionality for checking service and config consistency. The below figure gives the high level view of the service.

![Alt text](/design.png?style=centerme&raw=ture "High Level Architecture")

### Features

- run time updates of low level nginx + plugin specific configs
- api level (or request) security via access control plugin to control who can access or deny
- traffic controlling via rate limiter plugin to limit the api access in a given minute window
- fallback support of a request on error to an alternative end-point
- re-routing of a request based on different rules to support A/B testing scenarios
- config persistence by storing them along with service
- config data consistency check in pull model mode deployment of cluster in distributed environment

## Getting Started

The following instructions will help you get started with the service, and running on your local as well as deployment environment.

### Prerequisites

As of now, BloomGateway works on Debian based Linux operating system. All the necessary dependency will be installed with bloomgateway debian package.

We have tested with following environment,
  - Ubuntu (>= 14.04) [http://releases.ubuntu.com/14.04/](http://releases.ubuntu.com/14.04/)
  - OpenResty (==1.9.7.3): [https://openresty.org/en/download.html](https://openresty.org/en/download.html)

### Installation

Download the latest release version from [https://github.com/bloomreach/bloomgateway/releases](https://github.com/bloomreach/bloomgateway/releases) and run the below command.

```
sudo dpkg -i bloomgateway_0.10.4_amd64.deb
```

### Start Service

Start the service using,

```
sudo bloomgateway start
```

### Stop Service

Stop the service using,

```
sudo bloomgateway stop
```

### Verifying

By default, bloomgateway service runs on port 6070.

```
curl http://localhost:6070/
```

## Building from Source

Clone bloomgateway from github.

```
git clone https://github.com/bloomreach/bloomgateway.git
```

Build the debian package.

```
sudo bash build.sh
```

In case, if you want to skip tests,

```
sudo SKIPTEST=true bash build.sh
```

Once the package is ready, follow the same installation instructions mentioned above.

## POST API for controlling incoming requests

This section describes the POST API for controlling requests for security, throttling, re-routing and fallback scenario on error.
- The POST API is supported via default service port  **6071** .

### API

```
POST /update/config?type=plugin&name=<plugin name>&phase=<registered phase of plugin> --data JSON
```

* **URL Params**
  - type, name and phase are required params
  - name : plugin name.
    - Currently supported plugins are "access", "ratelimiter", "fallback" and "router"
  - phase : registered phase of the plugin.
    - Plugins "access, ratelimiter and fallback" are registered in the "access" phase of the request.
    - Plugin "fallback" is registered in the "error" phase of the request.

* **Data (Request Body)**
  - POST request body is a JSON Array where each JSON object describe a rule

* **Response:**
  - on success, returns
    - 200 HTTP_OK
  - on error, returns
    - 500 HTTP_INTERNAL_SERVER_ERROR
  - on invalid request,
    - 400 HTTP_BAD_REQUEST

### Data Model

This section describes the data model of supported plugins - access, ratelimiter, fallback and router.

#### Access Plugin

This plugin helps to control the api level security by denying the access to an API request either based on any header key/value pair or url param key/value pair.

##### JSON Rule Object

```
{
  "type": "object",
  "properties": {
    "type": {
      "description": "Specify either header or param",
      "type": "string"
    },
    "api": {
      "description": "URI of a request",
      "type": "string"
    },
    "key": {
      "description": "Name of the header or URL param key. Use remote_addr as key name for IP address",
      "type": "string"
    },
    "value": {
      "description": "Value of the key",
      "type": "string"
    },
    "access": {
      "description": "It should be either allow or deny. As of now, only supports deny.",
      "type": "string"
    }

  },
  "required": ["type", "api", "key", "value", "access"]
}
```

##### Example

In this example, all the reqeusts originating from IP : 10.10.10.101 are blocked for an API "/api/v1/core/". It also blocks all the requests if it contains URL param "account_id=1234".

```
curl -X POST http://localhost:6071/update/config?type=plugin&name=access&phase=access --data
'
[{
  "type": "header",
  "api": "/api/v1/core/",
  "key": "remote_addr",
  "value": "10.10.10.101",
  "access": "deny"
}, {
  "type": "param",
  "api": "/api/v1/core/",
  "key": "account_id",
  "value": "1234",
  "access": "deny"
}]
'
```

#### Rate Limiter Plugin

This plugin helps to throttle the traffic on upstream service. It supports configuring rule at node (or service level), using request URI, header key/value pair and URL param key/value pair. All the rules are defined for a minute window.

##### JSON Rule Object

```
{
  "type": "object",
  "properties": {
    "type": {
      "description": "Specify either node, api, header or param",
      "type": "string"
    },
    "api": {
      "description": "URI of a request. Not required if rule type is node",
      "type": "string"
    },
    "key": {
      "description": "Name of the header or URL param key. Not required if rule type is either api or node",
      "type": "string"
    },
    "value": {
      "description": "Value of the key. Not required for rule type is either api or node",
      "type": "string"
    },
    "threshold": {
      "description": "Max number of requests to allow in given minute window",
      "type": "string"
    }

  },
  "required": ["type", "api", "key", "value", "threshold"]
}
```

##### Example

In this example,
* allows maximum 50 requests per minute window of any types
* allows maximum 20 requests of an api /api/v1/core/
  - allows maximum 10 request which has account_id=1057 as URL param key
  - allows maximum 5 requests originating from IP : 10.10.10.101

```
curl -X POST http://localhost:6071/update/config?type=plugin&name=ratelimiter&phase=access --data
'
[{
  "type": "node",
  "threshold": "50"
}, {
  "type": "api",
  "api": "/api/v1/core/",
  "threshold": "20"
}, {
  "type": "param",
  "api": "/api/v1/core/",
  "key": "account_id",
  "value": "1057",
  "threshold": "10"
}, {
  "type": "header",
  "api": "/api/v1/core/",
  "key": "remote_addr",
  "value": "10.10.10.101",
  "threshold": "5"
}]
'
```

#### Router Plugin

This module helps to re-route requests to configured end-points. This is useful in scenarios,
- A/B testing
- Release workflow
- Re-grouping internal upstream servers

##### JSON Rule Object

```
{
  "type": "object",
  "properties": {
    "type": {
      "description": "Specify either header or param",
      "type": "string"
    },
    "api": {
      "description": "URI of a request.",
      "type": "string"
    },
    "key": {
      "description": "Name of the header or URL param key.",
      "type": "string"
    },
    "oneOf": [{
      "properties": {
        "value": {
          "description": "Value of the key.",
          "type": "string"
        },
        "required": ["value"]
      }
    }, {
      "properties": {
        "value_matches": {
          "description": "Regular expression for value.",
          "type": "string"
        },
        "required": ["value_matches"]
      }
    }],
    "endpoint": {
      "description": "host and port string of the end-point",
      "type": "string"
    }

  },
  "required": ["type", "api", "key", "endpoint"]
}
```

##### Example

In this example, we have configured re-routed requests for an api /api/v1/core/
- all the requests with URL param, account_id = 1057, are re-routed to A/B testing server
- all the requests with 5 digit keys starting with 1, are re-routed to set of upstream server of groupA

```
curl -X POST http://localhost:6071/update/config?type=plugin&name=router&phase=access --data
'
[{
  "type": "param",
  "api": "/api/v1/core/",
  "key": "account_id",
  "value": "1057",
  "endpoint": "upstream.abtest.elb.amazonaws:80"
}, {
  "type": "header",
  "api": "/api/v1/core/",
  "key": "api_key",
  "value_matches": "1[0-9]{4}",
  "endpoint": "upstream.groupA.elb.amazonaws:80"
}]
'
```

#### Fallback Plugin

This module allows to configure fallback rules in the error scenarios.
- Very useful in multi-data center scenarios when current data center is unavailable due to transient errors.
- Helps to point to central caching server to return results.
- Helps in dynamically changing end-points and its order in outages or similar worst scenarios.

At [BloomReach](http://www.bloomreach.com), we use this module in all the above scenario to increase our availability.

##### JSON Rule Object

```
{
  "type": "object",
  "properties": {
    "api": {
      "description": "URI of a request.",
      "type": "string"
    },
    "errors": {
      "description": "An array of 5xx errors to be handled",
      "type": "array",
      "items": {
        "type": "string"
      }
    },
    "key": {
      "description": "Unique key for this rule",
      "type": "string"
    },
    "endpoints": {
      "description": "List of an ordered endpoints to be tried",
      "type": "array",
      "items": {
        "type": "# /definitions/endpoint"
      }
    }
  },
  "definitions": {
    "endpoint": {
      "properties": {
        "headers": {
          "description": "Key/Value dict JSON object",
          "type": "object"
        },
        "params": {
          "description": "Key/value dict JSON object",
          "type": "object"
        },
        "name": {
          "description": "Endpoint host and port",
          "type": "string"
        }
      },
      "required": ["name", "params", "headers"]
    }
  },
  "required": ["api", "error", "key", "endpoints"]
}
```

##### Example

In this example, an API /api/v1/core/ is configured for fallback scenario on errors 5xx (500, 502, 503 and 504)
- first it tries with caching endpoint 'cache.elb.amazonaws' for failed request
  - it also passes an additional param 'fallback_cache_endpoint' to caching service for tracking or any other purpose
- on failure attempt from caching service, it tries with other data center 'west.elb.amazonaws:80'
  - here, it sends 'fallback_data_center_endpoint' as extra URL param
- if request fails with second attempt from other data center, it results into error and terminates further execution.

```
curl -X POST http://localhost:6071/update/config?type=plugin&name=fallback&phase=error --data
'
[{
  "endpoints": [{
    "1": {
      "headers": {},
      "params": {
        "fallback_cache_endpoint": "true"
      },
      "name": "cache.elb.amazonaws:80"
    }
  }, {
    "2": {
      "headers": {},
      "params": {
        "fallback_data_center_endpoint": "true"
      },
      "name": "west.elb.amazonaws:80"
    }
  }],
  "api": "/api/v1/core/",
  "errors": ["500", "502", "503", "504"],
  "key": "/api/v1/core/_500_502_503_504"
}]
'
```

## Running BloomGateway in PULL-config-update mode

Currently, BloomGateway only supports [AWS S3](https://aws.amazon.com/s3/) hook for pull mode. So, in pull-config-update mode, it depends on,
  - s3cmd (>=1.5.2): [https://github.com/s3tools/s3cmd/](https://github.com/s3tools/s3cmd/)
  - boto (>=2.5.1): [https://github.com/boto/boto](https://github.com/boto/boto)

To start the BloomGateway in PULL-config-update mode,

```
sudo bloomgateway start -i <cluster_id> -s <s3 location>
```

In pull mode, BloomGateway service pulls the all configuration from the central s3 location. You can use the s3cli.py command line interface to create/update those configs.

## More Information

Bloomreach Engineering Blog: http://engineering.bloomreach.com/bloomgateway-lightweight-entry-point-service/

## Versioning

BloomGateway is following date based versioning with the form <major>.<minor>.<path> as version tag. Here, <major> is the number of years passed since the project started, <minor> is the month, and <patch> represents the date.

## Contributors

* **Ronak Kothari** (ronak.kothari@gmail.com) - Project owner/Maintainer
* **Navneet Gupta** (navneetnitw@gmail.com)

## License

Apache License Version 2.0 http://www.apache.org/licenses/LICENSE-2.0

## Acknowledgments

BloomGateway uses couple of community libraries. We would like to thank and acknowledge their work.
* **Yichun "agentzh" Zhang** for OpenResty [https://github.com/openresty/openresty](https://github.com/juce/lua-resty-shell)
* **James Hurst** for lua-resty-http [https://github.com/pintsized/lua-resty-http](https://github.com/pintsized/lua-resty-http)
* **Juice** for lua-resty-shell [https://github.com/juce/lua-resty-shell](https://github.com/juce/lua-resty-shell)
* **Juice** for sockproc [https://github.com/juce/sockproc](https://github.com/juce/sockproc)
