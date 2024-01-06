from faker import Faker
import time

dataGenerator=Faker()
epoch=str(time.time_ns())+"-"
n=10
time.sleep(60) #Wait for kinesis agent to start
for j in range(30):
    with open("/tmp/data/"+epoch+str(j)+".log", "w") as file1:
        for i in range(n):
            data='{"username":"'+dataGenerator.name()+'",'+'"email":"'+dataGenerator.email()+'",'+'"phone_no":"'+dataGenerator.phone_number()+'",'+'"credit_card_number":"'+dataGenerator.credit_card_number()+'",'+'"billed":"'+str(dataGenerator.random_number())+'"},\n'
            if(i==n-1):
                data=data[:-2]+"\n"
            file1.write(data)
                
    print("written data")
    time.sleep(10)

