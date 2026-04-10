import paramiko
import os

host = 'gamessyd112.bisecthosting.com'
port = 2022
user = 'jacobe1128104.3c018d39'
pw = 'Fearless192!'

t = paramiko.Transport((host, port))
t.connect(username=user, password=pw)
sftp = paramiko.SFTPClient.from_transport(t)
print('CONNECTED!')

base = 'RSDragonwilds/Binaries/Win64'

# Upload dwmapi.dll
local_deploy = os.path.join(os.environ['TEMP'], 'server_deploy')
print('Uploading dwmapi.dll...')
sftp.put(os.path.join(local_deploy, 'dwmapi.dll'), base + '/dwmapi.dll')
print('  OK')

# Recursive upload
def upload_dir(local_path, remote_path):
    try:
        sftp.stat(remote_path)
    except FileNotFoundError:
        sftp.mkdir(remote_path)
        print('  Created: ' + remote_path)

    for item in os.listdir(local_path):
        local_item = os.path.join(local_path, item)
        remote_item = remote_path + '/' + item

        if os.path.isdir(local_item):
            upload_dir(local_item, remote_item)
        else:
            sftp.put(local_item, remote_item)
            print('  Uploaded: ' + remote_item)

print('Uploading ue4ss folder...')
upload_dir(os.path.join(local_deploy, 'ue4ss'), base + '/ue4ss')

print('\nDone! Files in Win64:')
for f in sftp.listdir(base):
    print('  ' + f)

print('\nMods:')
for f in sftp.listdir(base + '/ue4ss/Mods'):
    print('  ' + f)

sftp.close()
t.close()
