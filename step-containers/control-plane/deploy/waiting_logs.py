import logging
import os
import sys
import time

#
#   @brief This script is responsible for just logging until 
#

logging.basicConfig(level=logging.INFO,  stream=sys.stdout, format='%(asctime)-15s - %(levelno)s - %(message)s')

try:
    cf_deploy_flag_file=os.environ['cf_deploy_flag_file']
    cf_name=os.environ['cf_name']
    logging.info(f"cf_deploy_flag_file exists ({cf_deploy_flag_file})")
except Exception as e:
    logging.error("cf_deploy_flag_file environment variable not set")
    sys.exit(1)

#Check if file exists
while os.path.isfile(cf_deploy_flag_file):
    logging.info(f"Waiting {cf_name} Cloudformation to complete....")
    time.sleep(5)
    
logging.info("Flag file does not exists anymore, stop logging")