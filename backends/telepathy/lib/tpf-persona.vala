/*
 * Copyright (C) 2010 Collabora Ltd.
 *
 * This library is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authors:
 *       Travis Reitter <travis.reitter@collabora.co.uk>
 */

using Gee;
using GLib;
using TelepathyGLib;
using Folks;

/**
 * A persona subclass which represents a single instant messaging contact from
 * Telepathy.
 */
public class Tpf.Persona : Folks.Persona,
    AliasDetails,
    AvatarDetails,
    FavouriteDetails,
    GroupDetails,
    ImDetails,
    PresenceDetails
{
  private HashSet<string> _groups;
  private Set<string> _groups_ro;
  private bool _is_favourite;
  private string _alias;
  private HashMultiMap<string, ImFieldDetails> _im_addresses;
  private const string[] _linkable_properties = { "im-addresses" };
  private const string[] _writeable_properties =
    {
      "alias",
      "is-favourite",
      "groups"
    };

  /* Whether we've finished being constructed; this is used to prevent
   * unnecessary trips to the Telepathy service to tell it about properties
   * being set which are actually just being set from data it's just given us.
   */
  private bool _is_constructed = false;

  /**
   * Whether the Persona is in the user's contact list.
   *
   * This will be true for most {@link Folks.Persona}s, but may not be true for
   * personas where {@link Folks.Persona.is_user} is true. If it's false in
   * this case, it means that the persona has been retrieved from the Telepathy
   * connection, but has not been added to the user's contact list.
   *
   * @since 0.3.5
   */
  public bool is_in_contact_list { get; set; }

  /**
   * An avatar for the Persona.
   *
   * See {@link Folks.AvatarDetails.avatar}.
   *
   * @since UNRELEASED
   */
  public LoadableIcon? avatar { get; private set; }

  /**
   * The Persona's presence type.
   *
   * See {@link Folks.PresenceDetails.presence_type}.
   */
  public Folks.PresenceType presence_type { get; private set; }

  /**
   * The Persona's presence status.
   *
   * See {@link Folks.PresenceDetails.presence_status}.
   *
   * @since 0.5.UNRELEASED
   */
  public string presence_status { get; private set; }

  /**
   * The Persona's presence message.
   *
   * See {@link Folks.PresenceDetails.presence_message}.
   */
  public string presence_message { get; private set; }

  /**
   * The names of the Persona's linkable properties.
   *
   * See {@link Folks.Persona.linkable_properties}.
   */
  public override string[] linkable_properties
    {
      get { return this._linkable_properties; }
    }

  /**
   * {@inheritDoc}
   *
   * @since UNRELEASED
   */
  public override string[] writeable_properties
    {
      get { return this._writeable_properties; }
    }

  /**
   * An alias for the Persona.
   *
   * See {@link Folks.AliasDetails.alias}.
   */
  public string alias
    {
      get { return this._alias; }

      set
        {
          if (this._alias == value)
            return;

          if (this._is_constructed)
            ((Tpf.PersonaStore) this.store).change_alias (this, value);
          this._alias = value;
        }
    }

  /**
   * Whether this Persona is a user-defined favourite.
   *
   * See {@link Folks.FavouriteDetails.is_favourite}.
   */
  public bool is_favourite
    {
      get { return this._is_favourite; }

      set
        {
          if (this._is_favourite == value)
            return;

          if (this._is_constructed)
            ((Tpf.PersonaStore) this.store).change_is_favourite (this, value);
          this._is_favourite = value;
        }
    }

  /**
   * A mapping of IM protocol to an (unordered) set of IM addresses.
   *
   * See {@link Folks.ImDetails.im_addresses}.
   */
  public MultiMap<string, ImFieldDetails> im_addresses
    {
      get { return this._im_addresses; }
      private set {}
    }

  /**
   * A mapping of group ID to whether the contact is a member.
   *
   * See {@link Folks.GroupDetails.groups}.
   */
  public Set<string> groups
    {
      get { return this._groups_ro; }

      set
        {
          foreach (var group in value)
            {
              if (this._groups.contains (group) == false)
                this._change_group (group, true);
            }

          foreach (var group in this._groups)
            {
              if (value.contains (group) == false)
                this._change_group (group, true);
            }

          /* Since we're only changing the members of this._groups, rather than
           * replacing it with a new instance, we have to manually emit the
           * notification. */
          this.notify_property ("groups");
        }
    }

  /**
   * Add or remove the Persona from the specified group.
   *
   * See {@link Folks.GroupDetails.change_group}.
   */
  public async void change_group (string group, bool is_member)
    {
      if (this._change_group (group, is_member))
        {
          Tpf.PersonaStore store = (Tpf.PersonaStore) this.store;
          yield store._change_group_membership (this, group, is_member);
        }
    }

  private bool _change_group (string group, bool is_member)
    {
      var changed = false;

      if (is_member)
        {
          if (!this._groups.contains (group))
            {
              this._groups.add (group);
              changed = true;
            }
        }
      else
        changed = this._groups.remove (group);

      if (changed == true)
        this.group_changed (group, is_member);

      return changed;
    }

  /**
   * The Telepathy contact represented by this persona.
   *
   * Note that this may be `null` if the {@link PersonaStore} providing this
   * {@link Persona} isn't currently available (e.g. due to not being connected
   * to the network). In this case, most other properties of the {@link Persona}
   * are being retrieved from a cache and may not be current (though there's no
   * way to tell this).
   */
  public Contact? contact { get; construct; }

  /**
   * Create a new persona.
   *
   * Create a new persona for the {@link PersonaStore} `store`, representing
   * the Telepathy contact given by `contact`.
   *
   * @param contact the Telepathy contact being represented by the persona
   * @param store the persona store to place the persona in
   */
  public Persona (Contact contact, PersonaStore store)
    {
      unowned string id = contact.get_identifier ();
      var connection = contact.connection;
      var account = this._account_for_connection (connection);
      var uid = this.build_uid (store.type_id, store.id, id);

      Object (alias: contact.get_alias (),
              contact: contact,
              display_id: id,
              /* FIXME: This IID format should be moved out to the ImDetails
               * interface along with the code in
               * Kf.Persona.linkable_property_to_links(), but that depends on
               * bgo#624842 being fixed. */
              iid: account.get_protocol () + ":" + id,
              uid: uid,
              store: store,
              is_user: contact.handle == connection.self_handle);

      contact.notify["alias"].connect ((s, p) =>
          {
            if (this._alias != this.contact.alias)
              {
                this._alias = this.contact.alias;
                this.notify_property ("alias");
              }
          });

      debug ("Creating new Tpf.Persona '%s' for service-specific UID '%s': %p",
          uid, id, this);
      this._is_constructed = true;

      /* Set our single IM address */
      this._im_addresses = new HashMultiMap<string, ImFieldDetails> (
          null, null,
          (GLib.HashFunc) ImFieldDetails.hash,
          (GLib.EqualFunc) ImFieldDetails.equal);

      try
        {
          var im_addr = ImDetails.normalise_im_address (id,
              account.get_protocol ());
          var im_fd = new ImFieldDetails (im_addr);
          this._im_addresses.set (account.get_protocol (), im_fd);
        }
      catch (ImDetailsError e)
        {
          /* This should never happen…but if it does, warn of it and continue */
          warning (e.message);
        }

      /* Groups */
      this._groups = new HashSet<string> ();
      this._groups_ro = this._groups.read_only_view;

      contact.notify["avatar-file"].connect ((s, p) =>
        {
          this._contact_notify_avatar ();
        });
      this._contact_notify_avatar ();

      contact.notify["presence-message"].connect ((s, p) =>
        {
          this._contact_notify_presence_message ();
        });
      contact.notify["presence-type"].connect ((s, p) =>
        {
          this._contact_notify_presence_type ();
        });
      contact.notify["presence-status"].connect ((s, p) =>
        {
          this._contact_notify_presence_status ();
        });
      this._contact_notify_presence_message ();
      this._contact_notify_presence_type ();
      this._contact_notify_presence_status ();

      ((Tpf.PersonaStore) this.store).group_members_changed.connect (
          (s, group, added, removed) =>
            {
              if (added.find (this) != null)
                this._change_group (group, true);

              if (removed.find (this) != null)
                this._change_group (group, false);
            });

      ((Tpf.PersonaStore) this.store).group_removed.connect (
          (s, group, error) =>
            {
              /* FIXME: Can't use
               * !(error is TelepathyGLib.DBusError.OBJECT_REMOVED) because the
               * GIR bindings don't annotate errors */
              if (error != null &&
                  (error.domain != TelepathyGLib.dbus_errors_quark () ||
                   error.code != TelepathyGLib.DBusError.OBJECT_REMOVED))
                {
                  debug ("Group invalidated: %s", error.message);
                  this._change_group (group, false);
                }
            });
    }

  /**
   * Create a new persona for the {@link PersonaStore} `store`, representing
   * a cached contact for which we currently have no Telepathy contact.
   *
   * @param store The persona store to place the persona in.
   * @param uid The cached UID of the persona.
   * @param iid The cached IID of the persona.
   * @param im_address The cached IM address of the persona (excluding
   * protocol).
   * @param protocol The cached protocol of the persona.
   * @param groups The cached set of groups the persona is in.
   * @param is_favourite Whether the persona is a favourite.
   * @param alias The cached alias for the persona.
   * @param is_in_contact_list Whether the persona is in the user's contact
   * list.
   * @param is_user Whether the persona is the user.
   * @param avatar The icon for the persona's cached avatar, or `null` if they
   * have no avatar.
   * @return A new {@link Tpf.Persona} representing the cached persona.
   *
   * @since 0.5.UNRELEASED
   */
  internal Persona.from_cache (PersonaStore store, string uid, string iid,
      string im_address, string protocol, HashSet<string> groups,
      bool is_favourite, string alias, bool is_in_contact_list, bool is_user,
      LoadableIcon? avatar)
    {
      Object (contact: null,
              display_id: im_address,
              iid: iid,
              uid: uid,
              store: store,
              is_user: is_user);

      debug ("Creating new Tpf.Persona '%s' from cache: %p", uid, this);

      // IM addresses
      this._im_addresses = new HashMultiMap<string, ImFieldDetails> (null, null,
          (GLib.HashFunc) ImFieldDetails.hash,
          (GLib.EqualFunc) ImFieldDetails.equal);

      var im_fd = new ImFieldDetails (im_address);
      this._im_addresses.set (protocol, im_fd);

      // Groups
      this._groups = groups;
      this._groups_ro = this._groups.read_only_view;

      // Other properties
      this._alias = alias;
      this._is_favourite = is_favourite;
      this.is_in_contact_list = is_in_contact_list;
      this.avatar = avatar;

      // Make the persona appear offline
      this.presence_type = PresenceType.OFFLINE;
      this.presence_message = "";
    }

  ~Persona ()
    {
      debug ("Destroying Tpf.Persona '%s': %p", this.uid, this);
    }

  private static Account? _account_for_connection (Connection conn)
    {
      var manager = AccountManager.dup ();
      var accounts = manager.get_valid_accounts ();

      Account account_found = null;
      accounts.foreach ((l) =>
        {
          unowned Account account = (Account) l;
          if (account.connection == conn)
            {
              account_found = account;
              return;
            }
        });

      return account_found;
    }

  private void _contact_notify_presence_message ()
    {
      this.presence_message = this.contact.get_presence_message ();
    }

  private void _contact_notify_presence_type ()
    {
      this.presence_type = Tpf.Persona._folks_presence_type_from_tp (
          this.contact.get_presence_type ());
    }

  private void _contact_notify_presence_status ()
    {
      this.presence_status = this.contact.get_presence_status ();
    }

  private static PresenceType _folks_presence_type_from_tp (
      TelepathyGLib.ConnectionPresenceType type)
    {
      switch (type)
        {
          case TelepathyGLib.ConnectionPresenceType.AVAILABLE:
            return PresenceType.AVAILABLE;
          case TelepathyGLib.ConnectionPresenceType.AWAY:
            return PresenceType.AWAY;
          case TelepathyGLib.ConnectionPresenceType.BUSY:
            return PresenceType.BUSY;
          case TelepathyGLib.ConnectionPresenceType.ERROR:
            return PresenceType.ERROR;
          case TelepathyGLib.ConnectionPresenceType.EXTENDED_AWAY:
            return PresenceType.EXTENDED_AWAY;
          case TelepathyGLib.ConnectionPresenceType.HIDDEN:
            return PresenceType.HIDDEN;
          case TelepathyGLib.ConnectionPresenceType.OFFLINE:
            return PresenceType.OFFLINE;
          case TelepathyGLib.ConnectionPresenceType.UNKNOWN:
            return PresenceType.UNKNOWN;
          case TelepathyGLib.ConnectionPresenceType.UNSET:
            return PresenceType.UNSET;
          default:
            return PresenceType.UNKNOWN;
        }
    }

  private void _contact_notify_avatar ()
    {
      var file = this.contact.avatar_file;
      Icon? icon = null;

      if (file != null)
        icon = new FileIcon (file);

      if (this.avatar == null || icon == null || !this.avatar.equal (icon))
        this.avatar = (LoadableIcon) icon;
    }
}
