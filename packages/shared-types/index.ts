export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      auth_failed_attempts: {
        Row: {
          attempted_at: string
          id: string
          ip_address: string | null
          outcome: string
          tenant_id: string
          user_id: string | null
        }
        Insert: {
          attempted_at?: string
          id?: string
          ip_address?: string | null
          outcome: string
          tenant_id: string
          user_id?: string | null
        }
        Update: {
          attempted_at?: string
          id?: string
          ip_address?: string | null
          outcome?: string
          tenant_id?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "auth_failed_attempts_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      domain_events: {
        Row: {
          event_type: string
          id: string
          occurred_at: string
          payload: Json
          tenant_id: string
        }
        Insert: {
          event_type: string
          id?: string
          occurred_at?: string
          payload?: Json
          tenant_id: string
        }
        Update: {
          event_type?: string
          id?: string
          occurred_at?: string
          payload?: Json
          tenant_id?: string
        }
        Relationships: []
      }
      lead_projects: {
        Row: {
          lead_id: string
          project_id: string
          tenant_id: string
        }
        Insert: {
          lead_id: string
          project_id: string
          tenant_id: string
        }
        Update: {
          lead_id?: string
          project_id?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "lead_projects_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: false
            referencedRelation: "leads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lead_projects_project_id_fkey"
            columns: ["project_id"]
            isOneToOne: false
            referencedRelation: "projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lead_projects_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      lead_timeline: {
        Row: {
          actor_role: string | null
          actor_user_id: string | null
          event_type: Database["public"]["Enums"]["timeline_event_type"]
          id: string
          lead_id: string
          occurred_at: string
          payload: Json
          tenant_id: string
        }
        Insert: {
          actor_role?: string | null
          actor_user_id?: string | null
          event_type: Database["public"]["Enums"]["timeline_event_type"]
          id?: string
          lead_id: string
          occurred_at?: string
          payload?: Json
          tenant_id: string
        }
        Update: {
          actor_role?: string | null
          actor_user_id?: string | null
          event_type?: Database["public"]["Enums"]["timeline_event_type"]
          id?: string
          lead_id?: string
          occurred_at?: string
          payload?: Json
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "lead_timeline_actor_user_id_fkey"
            columns: ["actor_user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lead_timeline_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: false
            referencedRelation: "leads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lead_timeline_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      leads: {
        Row: {
          assigned_to_user_id: string | null
          budget_max: number | null
          budget_min: number | null
          created_at: string
          id: string
          interest_type: string | null
          is_incomplete: boolean
          last_action_at: string | null
          location: string | null
          name_encrypted: string | null
          name_search: string | null
          next_followup_at: string | null
          pending_outcome_at: string | null
          phone_encrypted: string
          phone_hash: string
          property_type: string | null
          remarks: string | null
          reschedule_count: number
          source: Database["public"]["Enums"]["lead_source"] | null
          status: Database["public"]["Enums"]["lead_status"]
          tenant_id: string
          ticket_size: string | null
          updated_at: string
          visit_date: string | null
        }
        Insert: {
          assigned_to_user_id?: string | null
          budget_max?: number | null
          budget_min?: number | null
          created_at?: string
          id?: string
          interest_type?: string | null
          is_incomplete?: boolean
          last_action_at?: string | null
          location?: string | null
          name_encrypted?: string | null
          name_search?: string | null
          next_followup_at?: string | null
          pending_outcome_at?: string | null
          phone_encrypted: string
          phone_hash: string
          property_type?: string | null
          remarks?: string | null
          reschedule_count?: number
          source?: Database["public"]["Enums"]["lead_source"] | null
          status?: Database["public"]["Enums"]["lead_status"]
          tenant_id: string
          ticket_size?: string | null
          updated_at?: string
          visit_date?: string | null
        }
        Update: {
          assigned_to_user_id?: string | null
          budget_max?: number | null
          budget_min?: number | null
          created_at?: string
          id?: string
          interest_type?: string | null
          is_incomplete?: boolean
          last_action_at?: string | null
          location?: string | null
          name_encrypted?: string | null
          name_search?: string | null
          next_followup_at?: string | null
          pending_outcome_at?: string | null
          phone_encrypted?: string
          phone_hash?: string
          property_type?: string | null
          remarks?: string | null
          reschedule_count?: number
          source?: Database["public"]["Enums"]["lead_source"] | null
          status?: Database["public"]["Enums"]["lead_status"]
          tenant_id?: string
          ticket_size?: string | null
          updated_at?: string
          visit_date?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "leads_assigned_to_user_id_fkey"
            columns: ["assigned_to_user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leads_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      projects: {
        Row: {
          created_at: string
          id: string
          is_active: boolean
          name: string
          tenant_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          is_active?: boolean
          name: string
          tenant_id: string
        }
        Update: {
          created_at?: string
          id?: string
          is_active?: boolean
          name?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "projects_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      tenants: {
        Row: {
          created_at: string
          id: string
          name: string
          timezone: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          timezone?: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          timezone?: string
        }
        Relationships: []
      }
      user_events: {
        Row: {
          actor_id: string | null
          event_type: Database["public"]["Enums"]["user_event_type"]
          id: string
          occurred_at: string
          payload: Json
          tenant_id: string
          user_id: string
        }
        Insert: {
          actor_id?: string | null
          event_type: Database["public"]["Enums"]["user_event_type"]
          id?: string
          occurred_at?: string
          payload?: Json
          tenant_id: string
          user_id: string
        }
        Update: {
          actor_id?: string | null
          event_type?: Database["public"]["Enums"]["user_event_type"]
          id?: string
          occurred_at?: string
          payload?: Json
          tenant_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_events_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_events_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_events_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      users: {
        Row: {
          bcrypt_password_hash: string
          created_at: string
          email_or_username: string
          id: string
          is_active: boolean
          locked_until: string | null
          must_change_password: boolean
          role: Database["public"]["Enums"]["user_role"]
          tenant_id: string
        }
        Insert: {
          bcrypt_password_hash: string
          created_at?: string
          email_or_username: string
          id?: string
          is_active?: boolean
          locked_until?: string | null
          must_change_password?: boolean
          role: Database["public"]["Enums"]["user_role"]
          tenant_id: string
        }
        Update: {
          bcrypt_password_hash?: string
          created_at?: string
          email_or_username?: string
          id?: string
          is_active?: boolean
          locked_until?: string | null
          must_change_password?: boolean
          role?: Database["public"]["Enums"]["user_role"]
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "users_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      auth_tenant_id: { Args: never; Returns: string }
      log_timeline_event: {
        Args: {
          p_event_type: Database["public"]["Enums"]["timeline_event_type"]
          p_lead_id: string
          p_payload?: Json
        }
        Returns: string
      }
      normalize_phone: { Args: { raw: string }; Returns: string }
      set_current_tenant: { Args: { tenant_id: string }; Returns: undefined }
    }
    Enums: {
      lead_source: "walk_in" | "referral" | "associate" | "ad"
      lead_status: "warm" | "cold" | "hot" | "dead" | "sold" | "future"
      timeline_event_type:
        | "lead_created"
        | "field_updated"
        | "status_changed"
        | "call_initiated"
        | "call_outcome_cleared"
        | "whatsapp_sent"
        | "followup_set"
        | "followup_rescheduled"
        | "followup_overdue"
        | "followup_completed"
        | "visit_date_set"
        | "visit_rescheduled"
        | "assigned"
        | "reassigned"
        | "shared"
        | "share_revoked"
        | "archived"
        | "restored"
        | "duplicate_override"
        | "remark_added"
        | "imported"
      user_event_type:
        | "account_created"
        | "account_deactivated"
        | "account_reactivated"
        | "password_changed"
        | "password_reset_by_admin"
        | "account_unlocked"
      user_role: "admin" | "employee"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      lead_source: ["walk_in", "referral", "associate", "ad"],
      lead_status: ["warm", "cold", "hot", "dead", "sold", "future"],
      timeline_event_type: [
        "lead_created",
        "field_updated",
        "status_changed",
        "call_initiated",
        "call_outcome_cleared",
        "whatsapp_sent",
        "followup_set",
        "followup_rescheduled",
        "followup_overdue",
        "followup_completed",
        "visit_date_set",
        "visit_rescheduled",
        "assigned",
        "reassigned",
        "shared",
        "share_revoked",
        "archived",
        "restored",
        "duplicate_override",
        "remark_added",
        "imported",
      ],
      user_event_type: [
        "account_created",
        "account_deactivated",
        "account_reactivated",
        "password_changed",
        "password_reset_by_admin",
        "account_unlocked",
      ],
      user_role: ["admin", "employee"],
    },
  },
} as const

// Story 1.1
export type Tenant = Tables<"tenants">
export type User = Tables<"users">
export type UserRole = Database["public"]["Enums"]["user_role"]
export type UserEvent = Tables<"user_events">
export type UserEventType = Database["public"]["Enums"]["user_event_type"]

// Story 2.1
export type Lead = Tables<"leads">
export type LeadInsert = TablesInsert<"leads">
export type LeadUpdate = TablesUpdate<"leads">
export type LeadStatus = Database["public"]["Enums"]["lead_status"]
export type LeadSource = Database["public"]["Enums"]["lead_source"]
export type Project = Tables<"projects">
export type ProjectInsert = TablesInsert<"projects">
export type LeadProject = Tables<"lead_projects">

// Story 2.2
export type LeadTimeline = Tables<"lead_timeline">
export type DomainEvent = Tables<"domain_events">
export type TimelineEventType = Database["public"]["Enums"]["timeline_event_type"]
