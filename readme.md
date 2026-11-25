



             CONTROL PLANE
          ┌──────────────────┐
          │ Admin API /      │
          │ Config Management│
          └────────┬─────────┘
                   │
                   ▼
                 etcd
                   │
             configuration
                   │
       ┌───────────┴───────────┐
       ▼                       ▼
 ┌───────────┐           ┌───────────┐
 │  APISIX-1 │           │  APISIX-2 │
 │ DATA PLANE│           │ DATA PLANE│
 └─────┬─────┘           └─────┬─────┘
       │                       │
       └───────────┬───────────┘
                   ▼
              LLM backends






                         USER / APPLICATION
                                │
                                ▼
                    ┌─────────────────────┐
                    │      APACHE APISIX  │
                    │      AI GATEWAY     │
                    └──────────┬──────────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
          ▼                    ▼                    ▼
    Prompt Guard         Prompt Decoration     Prompt Template
          │                    │                    │
          └────────────────────┼────────────────────┘
                               ▼
                         AI Rate Limit
                               │
                               ▼
                           AI Cache
                               │
                               ▼
                         AI Proxy / Multi
                               │
                 ┌─────────────┼─────────────┐
                 ▼             ▼             ▼
               OpenAI         vLLM        Anthropic
                API          VM-1/VM-2       API







                         CLIENT
                           │
                           ▼
                    ┌──────────────┐
                    │    APISIX    │
                    │  AI Gateway  │
                    └──────┬───────┘
                           │
                           ▼
                    Authentication
                           │
                           ▼
                     Prompt Guard
                           │
                           ▼
                  Prompt Decoration
                           │
                           ▼
                   Prompt Template
                           │
                           ▼
                     AI Rate Limit
                           │
                           ▼
                       AI Cache
                           │
                           ▼
                     AI Proxy
                           │
                           ▼
                   AI Proxy Multi
                           │
            ┌──────────────┼──────────────┐
            ▼              ▼              ▼
          OpenAI          vLLM        Anthropic
                           │
                      ┌────┴────┐
                      ▼         ▼
                    VM-1      VM-2