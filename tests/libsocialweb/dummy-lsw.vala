/*
 * Copyright (C) 2011 Collabora Ltd.
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
 * Authors: Alban Crequy <alban.crequy@collabora.co.uk>
 *
 */

using LibsocialwebTest;
using Folks;
using Gee;
using GLib;

public class DummyLswTests : Folks.TestCase
{
  private LibsocialwebTest.Backend _lsw_backend;

  public DummyLswTests ()
    {
      base ("DummyLsw");

      this._lsw_backend = new LibsocialwebTest.Backend ();

      this.add_test ("dummy libsocialweb", this.test_dummy_libsocialweb);
    }

  public override void set_up ()
    {
    }

  public override void tear_down ()
    {
    }

  public void test_dummy_libsocialweb ()
    {
      var main_loop = new GLib.MainLoop (null, false);

      this._lsw_backend.ready.connect(() =>
        {
          main_loop.quit ();
        });
      uint timer_id = Timeout.add_seconds (5, () =>
        {
          assert_not_reached ();
          return false;
        });
      this._lsw_backend.set_up ();
      main_loop.run ();
      Source.remove (timer_id);

      var mysocialnetwork = this._lsw_backend.add_service ("mysocialnetwork");
      var p = new GLib.HashTable<string,string> (null, null);

      try
        {
          var view_path = mysocialnetwork.OpenView("feed", p);
          var conn = Bus.get_sync (BusType.SESSION);
          conn.get_proxy<LibsocialwebTest.ContactView>
              .begin<LibsocialwebTest.ContactView> (
              "com.meego.libsocialweb", view_path, 0, null, (v) =>
            {
              LibsocialwebTest.ContactView view
                  = (LibsocialwebTest.ContactView)v;
              view.Start();
              mysocialnetwork.contact_views[view_path].ContactsAdded
                  (new LibsocialwebTest.LibsocialwebContactViewTest
                      .ContactsAddedElement[0]);
              mysocialnetwork.contact_views[view_path].ContactsAdded
                  (new LibsocialwebTest.LibsocialwebContactViewTest
                      .ContactsAddedElement[0]);
              main_loop.quit ();
            });
        }
      catch (GLib.IOError e)
        {
          assert_not_reached ();
        }


      timer_id = Timeout.add_seconds (5, () =>
        {
          assert_not_reached ();
        });
      main_loop.run ();
      Source.remove (timer_id);

      /* Ok, real test now */
      debug ("Ok, real test now");

      mysocialnetwork.OpenViewCalled.connect((query, p, path) =>
        {
          debug ("mysocialnetwork.OpenViewCalled.connect");
          mysocialnetwork.contact_views[path].StartCalled.connect ( (path) =>
            {
              debug ("OpenViewCalled.connect");
              Idle.add (() =>
                {
                  string text = "([('mysocialnetwork', 'id01', %x, "
                      + "{'id': ['id01'], 'name': ['Gargantua']}), "
                     + "('mysocialnetwork', 'id02', %x, "
                      + "{'id': ['id02'], 'name': ['Pantagruel']})],)";
                  Variant v = new Variant.parsed (text, 1300792578, 1300792579);
                  try
                    {
                      var conn = Bus.get_sync (BusType.SESSION);
                      conn.emit_signal (null, path,
                          "com.meego.libsocialweb.ContactView",
                          "ContactsAdded", v);
                    }
                  catch (GLib.IOError e)
                    {
                      assert_not_reached ();
                    }
                  catch (GLib.Error e)
                    {
                      assert_not_reached ();
                    }
                  return false;
                });
            });
        });

      var aggregator = new IndividualAggregator ();
      aggregator.individuals_changed.connect ((added, removed, m, a, r) =>
        {
          debug ("Aggregator got some data!");
          foreach (Individual i in added)
            {
              string nickname = ((Folks.NameDetails) i).nickname;
              debug ("nickname: %s", nickname);
            }
          main_loop.quit ();
        });
      aggregator.prepare ();

      timer_id = Timeout.add_seconds (5, () =>
        {
          assert_not_reached ();
        });
      main_loop.run ();
      Source.remove (timer_id);

      this._lsw_backend.tear_down ();
    }
}

public int main (string[] args)
{
  Test.init (ref args);

  TestSuite root = TestSuite.get_root ();
  root.add_suite (new DummyLswTests ().get_suite ());

  Test.run ();

  return 0;
}