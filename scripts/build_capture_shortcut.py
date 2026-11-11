#!/usr/bin/env python3
"""Build a secret-free iPhone Shortcuts template. Sign with Apple's `shortcuts sign`."""
import argparse
import plistlib
import uuid
from pathlib import Path


def build(origin):
    actions = []
    def action(name, **parameters):
        id = str(uuid.uuid4()).upper()
        actions.append({'WFWorkflowActionIdentifier':'is.workflow.actions.' + name,
                        'WFWorkflowActionParameters':parameters | {'UUID':id}})
        return {'Type':'ActionOutput','OutputUUID':id,'OutputName':'Результат'}
    def attachment(value): return {'Value':value,'WFSerializationType':'WFTextTokenAttachment'}
    def text(value):
        if isinstance(value,dict): return {'Value':{'string':'\ufffc','attachmentsByRange':{'{0, 1}':value}},'WFSerializationType':'WFTextTokenString'}
        return {'Value':{'string':value},'WFSerializationType':'WFTextTokenString'}
    def dictionary(values):
        return {'Value':{'WFDictionaryFieldValueItems':[
            {'WFItemType':0,'WFKey':text(key),'WFValue':text(value)} for key,value in values.items()
        ]},'WFSerializationType':'WFDictionaryFieldValue'}
    def lookup(source, key): return action('getvalueforkey', WFInput=attachment(source), WFDictionaryKey=text(key))
    def choose(source, prompt): return action('choosefromlist', WFInput=attachment(source), WFChooseFromListActionPrompt=prompt, WFChooseFromListActionSelectMultiple=False)
    def request(path, fields):
        auth={'Value':{'string':'Bearer \ufffc','attachmentsByRange':{'{7, 1}':key}},'WFSerializationType':'WFTextTokenString'}
        headers=dictionary({'Authorization':''})
        headers['Value']['WFDictionaryFieldValueItems'][0]['WFValue']=auth
        return action('downloadurl', WFURL=origin + path, WFHTTPMethod='POST', WFHTTPBodyType='JSON',
                      WFHTTPHeaders=headers, WFJSONValues=dictionary(fields))
    key=action('gettext', WFTextActionText='ВСТАВЬТЕ КЛЮЧ ИЗ НАСТРОЕК ТОЛКА')
    options=request('/api/capture/options',{})
    request_id=lookup(options,'requestID')
    ready_group=str(uuid.uuid4()).upper()
    action('conditional', WFInput={'Type':'Variable','Variable':attachment(request_id)},
           WFCondition=100, WFControlFlowMode=0, GroupingIdentifier=ready_group)
    title=action('ask', WFAskActionPrompt='Название задачи', WFInputType='Text', WFAskActionAllowMultiline=False)
    priorities=action('list', WFItems=['Без приоритета','Высокий','Средний','Низкий'])
    priority=choose(priorities,'Приоритет')
    group=str(uuid.uuid4()).upper()
    action('choosefrommenu', WFMenuPrompt='Дата задачи', WFMenuItems=['Без даты','Выбрать дату'], WFControlFlowMode=0, GroupingIdentifier=group)
    action('choosefrommenu', WFMenuItemTitle='Без даты', WFControlFlowMode=1, GroupingIdentifier=group)
    empty=action('gettext',WFTextActionText='')
    action('setvariable',WFVariableName='Дата задачи',WFInput=attachment(empty))
    action('choosefrommenu', WFMenuItemTitle='Выбрать дату', WFControlFlowMode=1, GroupingIdentifier=group)
    date=action('ask',WFAskActionPrompt='Дата задачи',WFInputType='Date')
    date=action('format.date',WFDate=text(date),WFDateFormatStyle='Custom',WFDateFormat='Custom',
                WFDateFormatString='yyyy-MM-dd',WFTimeFormatStyle='None')
    action('setvariable',WFVariableName='Дата задачи',WFInput=attachment(date))
    action('choosefrommenu',WFControlFlowMode=2,GroupingIdentifier=group)
    project=choose(lookup(options,'projectNames'),'Проект · без проекта выберите Входящие')
    project=lookup(lookup(options,'projects'),project)
    tag=choose(lookup(options,'tagNames'),'Тег')
    tag=lookup(lookup(options,'tags'),tag)
    result=request('/api/capture',{'requestID':request_id,'title':title,'priority':priority,
                                 'date':{'Type':'Variable','VariableName':'Дата задачи'},'projectID':project,'tagID':tag})
    # Both success and error are shown; never report success before the server answers.
    action('showresult',Text=text(lookup(result,'message')))
    action('conditional',WFControlFlowMode=1,GroupingIdentifier=ready_group)
    action('showresult',Text=text(lookup(options,'message')))
    action('conditional',WFControlFlowMode=2,GroupingIdentifier=ready_group)
    return {'WFWorkflowName':'Добавить в Толк','WFWorkflowClientVersion':'2700',
            'WFWorkflowMinimumClientVersion':900,'WFWorkflowMinimumClientVersionString':'900',
            'WFWorkflowIcon':{'WFWorkflowIconStartColor':0x598BFFFF,'WFWorkflowIconGlyphNumber':59511},
            'WFWorkflowActions':actions,'WFWorkflowInputContentItemClasses':[],
            'WFWorkflowOutputContentItemClasses':[],'WFWorkflowTypes':[],
            'WFWorkflowImportQuestions':[],'WFQuickActionSurfaces':[]}


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--origin',default='https://tolk.103-102-229-153.sslip.io')
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if not args.origin.startswith('https://'): parser.error('HTTPS origin required')
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_bytes(plistlib.dumps(build(args.origin.rstrip('/')),fmt=plistlib.FMT_BINARY))
