#!/usr/bin/env python

import requests
import json
import sys
import optparse
from optparse import OptionGroup
import os
from requests.packages.urllib3.exceptions import InsecureRequestWarning
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

changeprops = {
"KEYSTORELOC" : "/etc/amerstore",
"KEYPASS" : "amerkeypass",
"TRUSTSTORELOC" : "/etc/amertruststore",
"TRUSTSTOREPASS" : "amertruststore"
}


class propertiesupdater(object):
    def __init__(self, definitions):
        self.ambari = ambariProps(protocol, host, port, username, password, clustername)
        self.definitions = definitions
    def service(self, service):
        for site, props in self.definitions[service].iteritems():
                for prop, value in props.iteritems():
                    finalvalue = self.replacefunc(value)
                    execute = self.ambari.set(site, prop, finalvalue)
                    print(execute)
    def replacefunc(self, value):
        for key, prop in changeprops.iteritems():
            value = value.replace(key, prop)
        return(value)

class ambariProps(object):
    def __init__(self, protocol, host, port, username, password, clustername):
        self.command = '/var/lib/ambari-server/resources/scripts/configs.py -t %s -l %s -n %s -s %s -u %s -p %s ' % (password, port, host, username, protocol, clustername)
    def get(self, config, property):
        command = '%s -c %s -a %s %s' % (self.command, config, 'get')
        #rint(command)
        #result = os.system(command)
        return(command)
    def set(self, config, property, value):
        command = "%s -c %s -a %s %s '%s'" % (self.command, config, 'set', property, value)
        #print(command)
        #result = os.system(command)
        return(command)

def ambariREST(protocol, host, port, username, password, endpoint):
    url = protocol + "://" + host + ":" + port + "/" + endpoint
    try:
        r = requests.get(url, auth=(username, password), verify=False)
    except:
        print("Cannot connect to Ambari")
        sys.exit(1)
    return(json.loads(r.text))

def loaddefinitions():
    try:
        definitions = json.loads(open("./definitions.json").read())
    except:
        print("Cannot read defintions file")
        sys.exit(1)
    return(definitions)


def main():
    parser = optparse.OptionParser(usage="usage: %prog [options]")
    parser.add_option("-S", "--protocol", dest="protocol", default="http", help="default is http, set to https if required" )
    parser.add_option("-P", "--port", dest="port", default="8080", help="Set Ambari Protocol" )
    parser.add_option("-u", "--username", dest="username", default="admin", help="Ambari Username" )
    parser.add_option("-p", "--password", dest="password", default="admin", help="Ambari Password" )
    parser.add_option("-H", "--host", dest="host", default="localhost", help="Ambari Host" )

    (options, args) = parser.parse_args()
    global username
    global password
    global port
    global protocol
    global host
    global clustername
    username = options.username
    password = options.password
    port = options.port
    protocol = options.protocol
    host = options.host
    #clustername = ambariREST(protocol, host, port, username, password, "api/v1/clusters")["items"][0]["Clusters"]["cluster_name"]
    clustername = "amer"
    #installedservices = [ line["ServiceInfo"]["service_name"] for line in ambariREST(protocol, host, port, username, password, "api/v1/clusters/" + clustername + "/services" )["items"]]
    installedservices = ["ATLAS"]
    definitions = loaddefinitions()
    updater = propertiesupdater(definitions)
    for service in installedservices:
        if service in definitions.keys():
            updater.service(service)
        else:
            continue

if __name__ == "__main__":
  try:
    sys.exit(main())
  except (KeyboardInterrupt, EOFError):
    print("\nAborting ... Keyboard Interrupt.")
    sys.exit(1)
