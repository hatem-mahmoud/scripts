# SYNOPSIS
#   jira_model_classif_inference.py Code example using the model classifier for Ticket autoassign 
#
# EXEMPLE :
#  jira_model_classif_inference.py
#
# DESCRIPTION
#
#   Autoassign  of JIRA ticket using the BUILD Model
#   Some part of the code is sourced from https://developers.google.com/machine-learning/guides/text-classification
#   
#
#
# HISTORY
#
#   2022-03-28    Hatem mahmoud        creation
#
# REVISION
#
#
from jira import JIRA
import time
import datetime as d
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.base import MIMEBase
from email import encoders
import numpy as np
import matplotlib.pyplot as plt
import tensorflow as tf
from tensorflow.python.keras import models
from tensorflow.python.keras.layers import Dense
from tensorflow.python.keras.layers import Dropout
from sklearn import preprocessing
from collections import Counter
from sklearn.feature_extraction.text import CountVectorizer
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.feature_extraction.text import TfidfTransformer 
from sklearn.feature_selection import SelectKBest
from sklearn.feature_selection import f_classif
from sklearn.metrics import confusion_matrix,classification_report,ConfusionMatrixDisplay
from sklearn.metrics import accuracy_score
import pickle
from sys import maxsize
from numpy import set_printoptions


#Jira user, password and URL
user_name = '****'
password = '*****'
jira_url = '****'

#Tickets to assign
Issue_id = []
jquery_test_data  = 'status in ("OPEN") and assignee is EMPTY and created  >=  startOfMonth()  order by createdDate asc'
test_data = []
test_label = []



print('Program started. (' + d.datetime.now().strftime('%Y-%m-%d %H:%M:%S') + ')')

# Jira Server Connection
options = {'server': jira_url}
# Authentication
try:
    jira = JIRA(options, basic_auth=(f'{user_name}', f'{password}'))
    print('Program connected. (' + d.datetime.now().strftime('%Y-%m-%d %H:%M:%S') + ')')
except BaseException as Be:
    print(Be)


count = 0
while True:
    print('Program Testing data.  (' + d.datetime.now().strftime('%Y-%m-%d %H:%M:%S') + ') lot : ', count )
    i = 0
    if count > 1000 :       
        break  
    all_closed_issues_inference = jira.search_issues(
        jquery_test_data , startAt=count,maxResults=999)          
    if len(all_closed_issues_inference) == 0:       
        break    
    for i in range(0, len(all_closed_issues_inference)):       
        Issue_id.append(str(all_closed_issues_inference[i].key))
        test_data.append(..
    count += 999

print('Number of Testing sample ',len(test_data))  
if len(test_data) == 0:
    quit()

                    
#Load Encoder
trle = pickle.load(open("LabelEncoder.pkl", "rb"))
model = tf.keras.models.load_model('JIRA_mlp_model.h5')

# Check model architecture
model.summary()
                                                                   

# Vectorize training texts.  
loaded_vec = pickle.load(open("feature.pkl", "rb"))     
x_test = loaded_vec.transform(test_data)    

# Select top 'k' of the vectorized features.
loaded_sel = pickle.load(open("selector.pkl", "rb"))
x_test = loaded_sel.transform(x_test).todense()


set_printoptions(threshold=maxsize)

mlp_predictions = model.predict(x_test)
y_classes = mlp_predictions.argmax(axis=-1)

 
print('-------------Model prediction-----------')    

for i in range(len(x_test)):
      print("Issue=%s , Predicted=%s, prob=%s" % (Issue_id[i], trle.inverse_transform([y_classes[i]]),max(mlp_predictions[i])))    
        issues_Jql = jira.issue(Issue_id[i],expand='changelog')  
        issues_Jql.update({'customfield_10210':  {'value':)  
        issues_Jql.assign_issue(Issue_id[i], None)

