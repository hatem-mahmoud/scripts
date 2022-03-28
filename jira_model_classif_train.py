# SYNOPSIS
#   jira_model_classif_train.py Code example for training a JIRA model classifier 
#
# EXEMPLE :
#  jira_model_classif_train.py
#
# DESCRIPTION
#
#   Training a JIRA model classifier (MLP) 
#   Some part of the code is sourced from https://developers.google.com/machine-learning/guides/text-classification
#   
#
#
# HISTORY
#
#   2022-03-04    HM        creation
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
from sklearn.feature_extraction.text import CountVectorizer
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.feature_selection import SelectKBest
from sklearn import model_selection, naive_bayes, svm
from sklearn.tree import DecisionTreeClassifier
from sklearn.feature_selection import f_classif
from sklearn.metrics import confusion_matrix,classification_report
from collections import Counter
from keras.regularizers import l2
from keras.regularizers import l1
from sklearn.metrics import accuracy_score
from sklearn.utils import class_weight
import pickle
from sys import maxsize
from numpy import set_printoptions


#Jira user, password and URL
user_name = '****'
password = '*****'
jira_url = '****'


#Training, validation and testing dataset 
jquery_train_data  = 'status in ("Closed - To Confirm", Closed) and assignee is not EMPTY and created > startOfMonth(-8)  and created < startOfMonth(-3) order by createdDate asc'
train_data = []
train_label = []
jquery_valid_data  = 'status in ("Closed - To Confirm", Closed) and assignee is not EMPTY and created > startOfMonth(-3)   and created < startOfMonth(-2)  order by createdDate asc'
valid_data = []
valid_label = []
jquery_test_data  = 'status in ("Closed - To Confirm", Closed) and assignee is not EMPTY and created > startOfMonth(-2)    and created < startOfMonth(-1)   order by createdDate asc'
test_data = []
test_label= []


#Record best model accuracy 
model_best_accuracy = 0


# Vectorization parameters
# Range (inclusive) of n-gram sizes for tokenizing text.
NGRAM_RANGE = (1, 2)

# Limit on the number of features. We use the top 20K features.
TOP_K = 20000

# Whether text should be split into word or character n-grams.
# One of 'word', 'char'.
TOKEN_MODE = 'word'

# Minimum document/corpus frequency below which a token will be discarded.
MIN_DOCUMENT_FREQUENCY = 2


def train_ngram_model(train_texts, train_labels, val_texts, val_labels, test_texts, test_labels,
                      lr=1e-3,
                      epochs=1000,
                      batch_size=128,
                      layers=2,
                      units=64,
                      dropout_rate=0.2,
                      l2_regularization=0.0001):
    """Trains n-gram model on the given dataset.

    # Arguments
        train_texts, train_labels, val_texts, val_labels, test_texts, test_labels: tuples of training, validation and test texts and labels.
        lr: float, learning rate for training model.
        epochs: int, number of epochs.
        batch_size: int, number of samples per batch.
        layers: int, number of `Dense` layers in the model.
        units: int, output dimension of Dense layers in the model.
        dropout_rate: float: percentage of input to drop at Dropout layers.
        l2_regularization: float: Degree of weight decay (L2 weight regularization).

    # Raises
        ValueError: If validation data has label values which were not seen
            in the training data.
    """
    # Get the data.
   # train_texts, train_labels, val_texts, val_labels, test_texts, test_labels

    # Verify that validation labels are in the same range as training labels.
    num_classes = get_num_classes(train_labels)
    unexpected_labels = [v for v in val_labels if v not in range(num_classes)]
    if len(unexpected_labels):
        raise ValueError('Unexpected label values found in the validation set:'
                         ' {unexpected_labels}. Please make sure that the '
                         'labels in the validation set are in the same range '
                         'as training labels.'.format(
                             unexpected_labels=unexpected_labels))

    # Vectorize texts.
    x_train, x_val, x_test = ngram_vectorize(
        train_texts, train_labels, val_texts, test_texts)

    # Create model instance.
    model = mlp_model(layers=layers,
                                  units=units,
                                  dropout_rate=dropout_rate,
                                  input_shape=x_train.shape[1:],
                                  num_classes=num_classes,
                                  l2_regularization=l2_regularization)

    # Compile model with learning parameters.
    if num_classes == 2:
        loss = 'binary_crossentropy'
    else:
        loss = 'sparse_categorical_crossentropy'
    optimizer = tf.keras.optimizers.Adam(learning_rate=lr)
    model.compile(optimizer= 'adam', loss=loss, metrics=['acc'])

    # Create callback for early stopping on validation loss. If the loss does
    # not decrease in two consecutive tries, stop training.
    callbacks = [tf.keras.callbacks.EarlyStopping(
        monitor='val_loss', patience=2)]     
     

    #Adjust class Weight
    class_weights = class_weight.compute_class_weight(class_weight = 'balanced',classes = np.unique(train_labels),y = train_labels)
    class_weights = dict(enumerate(class_weights))

    # Train and validate model.
    history = model.fit(
            x_train,
            train_labels,
            epochs=epochs,
            callbacks=callbacks,
            #class_weight=class_weights,
            validation_data=(x_val, val_labels),            
            verbose=2,  # Logs once per epoch.
            batch_size=batch_size)
    
    # Print results.
    history = history.history
    print('Validation accuracy: {acc}, loss: {loss}'.format(
            acc=history['val_acc'][-1], loss=history['val_loss'][-1]))
            
    # Evaluate the model
    loss, acc_t = model.evaluate(x_test, test_labels, verbose=2)
    print("Model test, accuracy: {:5.2f}%".format(100 * acc_t)) 

    

        
    set_printoptions(threshold=maxsize)
    
    mlp_predictions = model.predict(x_test)
    # creating a confusion matrix
    cm_mlp = confusion_matrix( np.array(test_labels),  mlp_predictions.argmax(axis=1)) 
    print('MLP test confusion_matrix')
    print(cm_mlp)
    print('Classification Report')
    print(classification_report(np.array(test_labels),  mlp_predictions.argmax(axis=1)))
    #print(mlp_predictions)    
    global model_best_accuracy
    if model_best_accuracy < acc_t:
        print("Model with better test, accuracy: {:5.2f}%".format(100 * acc_t)) 
        model_best_accuracy=acc_t 
        # Save model.
        model.save('JIRA_mlp_model.h5')
    
    #Try other classifier 
    ## Classifier - Algorithm - NB classifier
    #Naive = naive_bayes.MultinomialNB()
    #Naive.fit(x_val,val_labels)
    ## predict the labels on validation dataset
    #predictions_NB = Naive.predict(x_test)
    ## Use accuracy_score function to get the accuracy
    #print("Naive Bayes Accuracy Score -> ",accuracy_score(predictions_NB, np.array(test_labels))*100)  
    #
    ## Classifier - Algorithm - SVM
    ## fit the training dataset on the classifier
    #SVM = svm.SVC(kernel='linear')
    #SVM.fit(x_train,train_labels)
    ## predict the labels on validation dataset
    #predictions_SVM = SVM.predict(x_test)
    ## Use accuracy_score function to get the accuracy
    #print("SVM Accuracy Score -> ",accuracy_score(predictions_SVM, test_labels)*100)  
    #
    ## Classifier - Algorithm -  a DescisionTreeClassifier
    #
    #dtree_model = DecisionTreeClassifier(max_depth = 2).fit( np.array(x_train), np.array( train_labels))
    #dtree_predictions = dtree_model.predict( np.array(x_val))
    #
    #score = accuracy_score( np.array(val_labels),  np.array(dtree_predictions))
    #print("dtree train, accuracy:",score )   
    ## creating a confusion matrix
    #cm = confusion_matrix( np.array(val_labels),  np.array(dtree_predictions))   
    #print('dtree train confusion_matrix')
    #print(cm)  
    
    return history['val_acc'][-1], history['val_loss'][-1]
    

def mlp_model(layers, units, dropout_rate, input_shape, num_classes,l2_regularization):
    """Creates an instance of a multi-layer perceptron model.

    # Arguments
        layers: int, number of `Dense` layers in the model.
        units: int, output dimension of the layers.
        dropout_rate: float, percentage of input to drop at Dropout layers.
        input_shape: tuple, shape of input to the model.
        num_classes: int, number of output classes.
        l2_regularization:float: Degree of weight decay (L2 weight regularization).

    # Returns
        An MLP model instance.
    """
    op_units, op_activation = _get_last_layer_units_and_activation(num_classes)
    model = models.Sequential()
    model.add(Dropout(rate=dropout_rate, input_shape=input_shape))

    for _ in range(layers-1):
        model.add(Dense(units=units, activation='relu'
        ,kernel_regularizer=l2(l2_regularization)
        ))
        model.add(Dropout(rate=dropout_rate))

    model.add(Dense(units=op_units, activation=op_activation))
    return model

def _get_last_layer_units_and_activation(num_classes):
    """Gets the # units and activation function for the last network layer.

    # Arguments
        num_classes: int, number of classes.

    # Returns
        units, activation values.
    """
    if num_classes == 2:
        activation = 'sigmoid'
        units = 1
    else:
        activation = 'softmax'
        units = num_classes
    return units, activation

def ngram_vectorize(train_texts, train_labels, val_texts,test_texts):
    """Vectorizes texts as n-gram vectors.

    1 text = 1 tf-idf vector the length of vocabulary of unigrams + bigrams.

    # Arguments
        train_texts: list, training text strings.
        train_labels: np.ndarray, training labels.
        val_texts: list, validation text strings.
        test_texts:list, testing text strings.

    # Returns
        x_train, x_val, x_test: vectorized training , validation and test texts
    """
    # Create keyword arguments to pass to the 'tf-idf' vectorizer.
    kwargs = {
            'ngram_range': NGRAM_RANGE,  # Use 1-grams + 2-grams.
            'dtype': 'int32',
            'strip_accents': 'unicode',
            'decode_error': 'replace',
            'analyzer': TOKEN_MODE,  # Split text into word tokens.
            'min_df': MIN_DOCUMENT_FREQUENCY,
    }
    vectorizer = TfidfVectorizer(**kwargs)

    # Learn vocabulary from training texts and vectorize training texts.
    x_train = vectorizer.fit_transform(train_texts)

    # Vectorize validation texts.
    x_val = vectorizer.transform(val_texts)
    
    # Vectorize test texts.
    x_test = vectorizer.transform(test_texts)
    
    #Save vectorizer
    pickle.dump(vectorizer,open("feature.pkl","wb"))

    # Select top 'k' of the vectorized features.
    selector = SelectKBest(f_classif, k=min(TOP_K, x_train.shape[1]))
    selector.fit(x_train, train_labels)
    x_train = selector.transform(x_train).todense()
    x_val = selector.transform(x_val).todense()
    x_test = selector.transform(x_test).todense()
    #Save selector
    pickle.dump(selector,open("selector.pkl","wb"))
    return x_train, x_val, x_test

def get_num_classes(labels):
    """Gets the total number of classes.
    # Arguments
        labels: list, label values.
            There should be at lease one sample for values in the
            range (0, num_classes -1)
    # Returns
        int, total number of classes.
    # Raises
        ValueError: if any label value in the range(0, num_classes - 1)
            is missing or if number of classes is <= 1.
    """
    num_classes = max(labels) + 1
    missing_classes = [i for i in range(num_classes) if i not in labels]
    if len(missing_classes):
        raise ValueError('Missing samples with label value(s) '
                         '{missing_classes}. Please make sure you have '
                         'at least one sample for every label value '
                         'in the range(0, {max_class})'.format(
                            missing_classes=missing_classes,
                            max_class=num_classes - 1))

    if num_classes <= 1:
        raise ValueError('Invalid number of labels: {num_classes}.'
                         'Please make sure there are at least two classes '
                         'of samples'.format(num_classes=num_classes))
    return num_classes


def plot_class_distribution(labels):
    """Plots the class distribution.
    # Arguments
        labels: list, label values.
            There should be at lease one sample for values in the
            range (0, num_classes -1)
    """
    num_classes = get_num_classes(labels)
    count_map = Counter(labels)
    counts = [count_map[i] for i in range(num_classes)]
    idx = np.arange(num_classes)
    plt.bar(idx, counts, width=0.8, color='b')
    plt.xlabel('Class')
    plt.ylabel('Number of samples')
    plt.title('Class distribution')
    plt.xticks(idx, idx)
    plt.show()




print('Program started. (' + d.datetime.now().strftime('%Y-%m-%d %H:%M:%S') + ')')

# Jira Server Connection
options = {'server': jira_url}
# Authentication
try:
    jira = JIRA(options, basic_auth=(f'{user_name}', f'{password}'))
    print('Program connected. (' + d.datetime.now().strftime('%Y-%m-%d %H:%M:%S') + ')')
except BaseException as Be:
    print(Be)



#Load last saved training data
#train_data = pickle.load(open("train_data.pkl", "rb"))
#train_label = pickle.load(open("train_label.pkl", "rb"))

count = 0
while True:
    print('Program Training data. (' + d.datetime.now().strftime('%Y-%m-%d %H:%M:%S') + ') lot : ', count )
    i = 0
    if count > 50000 :       
        break  
    all_closed_issues_training = jira.search_issues(
        jquery_train_data, startAt=count,maxResults=999 )          
    if len(all_closed_issues_training) == 0:       
        break    
    for i in range(0, len(all_closed_issues_training)):
        train_data.append(...
        train_label.append(...
       
    count += 999

print('Number of training sample ',len(train_data))  

pickle.dump(train_data,open("train_data.pkl","wb"))
pickle.dump(train_label,open("train_label.pkl","wb"))

#Encode training Label
trle = preprocessing.LabelEncoder()
train_label_e=trle.fit_transform(train_label)
print(list(trle.classes_))
print('Number of training classes : ' , get_num_classes( np.array(train_label_e)))
plot_class_distribution(np.array(train_label_e))
#print(list(train_label_e))
#print(trle.inverse_transform([0]))

#Save Label Encoder
pickle.dump(trle,open("LabelEncoder.pkl","wb"))

#valid_data = pickle.load(open("valid_data.pkl", "rb"))
#valid_label = pickle.load(open("valid_label.pkl", "rb"))

count = 0
while True:
    print('Program Validation data. (' + d.datetime.now().strftime('%Y-%m-%d %H:%M:%S') + ') lot : ', count )
    i = 0
    if count > 2000 :       
        break  
    all_closed_issues_validation = jira.search_issues(
        jquery_valid_data, startAt=count,maxResults=999 )          
    if len(all_closed_issues_validation) == 0:       
        break    
    for i in range(0, len(all_closed_issues_validation)):
        valid_data.append(...
        valid_label.append(...
    count += 999         
            
       
      
print('Number of validation sample ',len(valid_data))

pickle.dump(valid_data,open("valid_data.pkl","wb"))
pickle.dump(valid_label,open("valid_label.pkl","wb"))  

#Encode testing Label
#valle = preprocessing.LabelEncoder()
valid_label_e=trle.transform(valid_label)
#print(list(valle.classes_))
print('Number of validation classes : ' , get_num_classes( np.array(valid_label_e)))
#plot_class_distribution(np.array(valid_label_e))
#print(list(valid_label))
#print(valle.inverse_transform([0]))
     
#test_data = pickle.load(open("test_data.pkl", "rb"))
#test_label = pickle.load(open("test_label.pkl", "rb"))

count = 0
while True:
    print('Program Testing data. (' + d.datetime.now().strftime('%Y-%m-%d %H:%M:%S') + ') lot : ', count )
    i = 0
    if count > 2000 :       
        break  
    all_closed_issues_testing = jira.search_issues(
        jquery_test_data, startAt=count,maxResults=999 )          
    if len(all_closed_issues_testing) == 0:       
        break    
    for i in range(0, len(all_closed_issues_testing)):
        test_data.append(...
        test_label.append(...
    count += 999    
       
      
print('Number of testing sample ',len(test_data))  

pickle.dump(test_data,open("test_data.pkl","wb"))
pickle.dump(test_label,open("test_label.pkl","wb"))  

#Encode testing Label
#ttle = preprocessing.LabelEncoder()
test_label_e=trle.transform(test_label)
#print(list(ttle.classes_))
#print('Number of testing classes : ' , get_num_classes( np.array(test_label_e)))
#plot_class_distribution(np.array(test_label_e))
#print(unique(list(test_label_e)))
#print(ttle.inverse_transform([0]))
        



#train_ngram_model(train_data, np.array(train_label_e),valid_data, np.array(valid_label_e),test_data, np.array(test_label_e))      

#HP Tunning using Grid search
for dropout_rate in [0.2,0.3]:
  for batch_size in [8,16,32,64,128]:
   for layers in [2,3,4]:
    for units in [16,32,64,128]:
     for l2_regularization in [0.0001,0.0002]:
      for lr in [1e-3]:
       print("Testing HP :",dropout_rate,batch_size,layers,units,l2_regularization,lr)
       train_ngram_model(train_data, np.array(train_label_e),valid_data, np.array(valid_label_e),test_data, np.array(test_label_e),1e-3,
                        1000,
                        batch_size,
                        layers,
                        units,
                        dropout_rate,
                        l2_regularization)
       
