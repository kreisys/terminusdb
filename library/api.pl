:- module(api,[]).

/** <module> HTTP API
 * 
 * The Terminus DB API interface.
 * 
 * A RESTful endpoint inventory for weilding the full capabilities of the 
 * terminusDB. 
 *
 * * * * * * * * * * * * * COPYRIGHT NOTICE  * * * * * * * * * * * * * * *
 *                                                                       *
 *  This file is part of TerminusDB.                                     *
 *                                                                       *
 *  TerminusDB is free software: you can redistribute it and/or modify   *
 *  it under the terms of the GNU General Public License as published by *
 *  the Free Software Foundation, either version 3 of the License, or    *
 *  (at your option) any later version.                                  *
 *                                                                       *
 *  TerminusDB is distributed in the hope that it will be useful,        *
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of       *
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the        *
 *  GNU General Public License for more details.                         *
 *                                                                       *
 *  You should have received a copy of the GNU General Public License    *
 *  along with TerminusDB.  If not, see <https://www.gnu.org/licenses/>. *
 *                                                                       *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

% http libraries
:- use_module(library(http/http_log)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_server_files)).
:- use_module(library(http/html_write)).
:- use_module(library(http/http_path)).
:- use_module(library(http/html_head)).
:- use_module(library(http/http_parameters)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_client)).
:- use_module(library(http/http_header)).
:- use_module(library(http/json)). 
:- use_module(library(http/json_convert)).

% Load capabilities library
:- use_module(library(capabilities)).

% woql libraries
:- use_module(library(woql_compile)).

% Default utils
:- use_module(library(utils)).

% Database utils
:- use_module(library(database_utils)).

% Graph construction utils
:- use_module(library(collection)).

% Frame and entity processing
:- use_module(library(frame)).

%% Set base location
% We may want to allow this as a setting...
http:location(root, '/', []).

%%%%%%%%%%%%% API Paths %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

:- http_handler(root(.), connect_handler, []). 
:- http_handler(root(DB), db_handler(Method,DB),
                [method(Method),
                 methods([post,delete])]).
:- http_handler(root(DB/schema), schema_handler(Method,DB), 
                [method(Method),
                 methods([get,post])]).
:- http_handler(root(DB/document/DocID), document_handler(Method,DB,DocID),
                [method(Method),
                 methods([get,post,delete])]). 
:- http_handler(root(DB/woql), woql_handler(Method,DB),
                [method(Method),
                 methods([get,post,delete])]). 
:- http_handler(root(DB/search), search_handler(Method,DB),
                [method(Method),
                 methods([get,post,delete])]). 

%%%%%%%%%%%%%%%%%%%% Access Rights %%%%%%%%%%%%%%%%%%%%%%%%%

/* 
 * verify_capability(+Request:http_request,+Capability) is det. 
 * 
 * This should either be true or throw an http_reply message. 
 */
verify_capability(Request,Capability) :-
    http_parameters(Request, [], [form_data(Data)]),

    (   member(key=Key, Data)
    ->  true
    ;   throw(http_reply(authorise('No key supplied')))),

    (   key_user(Key, User)
    ->  true
    ;   throw(http_reply(authorise('Not a valid key')))),

    (   user_action(User,Capability)
    ->  true
    ;   throw(http_reply(method_not_allowed(Capability)))).

/* 
 * authenticate(+Data,+Auth_Obj) is det. 
 * 
 * This should either bind the Auth_Obj or throw an http_status_reply/4 message. 
 */
authenticate(Request, Auth) :-
    http_parameters(Request, [], [form_data(Data)]),
    
    (   memberchk(key=Key, Data)        
    ->  true
    ;   throw(http_reply(authorise('No key supplied')))),

    (   key_auth(Key, Auth)
    ->  true
    ;   throw(http_reply(authorise('Not a valid key')))).

verify_access(Auth, Action, Scope) :-
    (   auth_action_scope(Auth, Action, Scope)
    ->  true
    ;   throw(http_reply(method_not_allowed(Action,Scope)))).


%%%%%%%%%%%%%%%%%%%% Connection Handlers %%%%%%%%%%%%%%%%%%%%%%%%%

/** 
 * connect_handler(Request:http_request) is det.
 */
connect_handler(Request) :-
    authenticate(Request,Auth),
    
    format('Content-type: application/json~n~n'),
    current_output(Out),
	json_write_dict(Out,Auth).

/** 
 * db_handler(Request:http_request,Method:atom,DB:atom) is det.
 */
db_handler(post,DB,Request) :-
    /* POST: Create database */
    authenticate(Request, Auth),
    
    verify_access(Auth,terminus/create_database,terminus/server),

    create_db(DB),
    
    format('Content-type: application/json~n~n'),
    
    current_output(Out),
	json_write_dict(Out,_{'terminus:status' : 'success'}).
db_handler(delete,DB,Request) :-
    /* DELETE: Delete database */
    authenticate(Request, Auth),
    
    verify_access(Auth,terminus/delete_database,terminus/server),
    
    delete_db(DB),
    
    format('Content-type: application/json~n~n'),
    current_output(Out),
	json_write_dict(Out,_{'terminus:status' : 'success'}).
    
/** 
 * woql_handler(+Request:http_request) is det.
 */ 
woql_handler(Request) :-
    authenticate(Request, Auth),

    http_parameters(Request, [], [form_data(Data)]),
    
    get_key(query,Data,Query),
    http_log_stream(Log),
    run_query(Query, JSON),
    
    * format(Log,'Query: ~q~nResults in: ~q~n',[Query,JSON]),
    format('Content-type: application/json~n~n'),
    current_output(Out),
	json_write_dict(Out,JSON).

document_handler(get, DB, Doc_ID, Request) :-
    /* Read Document */
    authenticate(Request, Auth),
    
    config:server_name(Server_Name),
    interpolate([Server_Name,DB],DB_URI),
    
    % check access rights
    verify_access(Auth,terminus/get_document,DB_URI),
    
    make_collection_graph(DB_URI,Graph),
    interpolate([DB_URI,'/',document, '/',Doc_ID],Doc_URI),
    format('Content-type: application/json~n~n'),    
    (   entity_jsonld(Doc_URI,Graph,JSON)
    ->  current_output(Out),
        json_write_dict(Out,JSON),
        writeq(Request)
    ;   writeq(entity_jsonld(Doc_URI,Graph,_))).
document_handler(post, DB, Doc_ID, Request) :-
    /* Update Document */
    authenticate(Request, Auth),

    config:server_name(Server_Name),
    interpolate([Server_Name,DB],DB_URI),

    % check access rights
    verify_access(terminus/create_document,Auth,DB_URI),
    
    make_collection_graph(DB,Graph),
    entity_jsonld(Doc_ID,Graph,JSON),
    
    format('Content-type: application/json~n~n'),
    current_output(Out),
	json_write_dict(Out,JSON).
document_handler(delete, DB, Doc_ID, Request) :-
    /* Delete Document */
    authenticate(Request, Auth),

    config:server_name(Server_Name),
    interpolate([Server_Name,DB],DB_URI),
    
    % check access rights
    verify_access(terminus/delete_document,Auth,DB_URI),
    
    make_collection_graph(DB,Graph),
    entity_jsonld(Doc_ID,Graph,JSON),
    
    format('Content-type: application/json~n~n'),
    current_output(Out),
	json_write_dict(Out,JSON).
